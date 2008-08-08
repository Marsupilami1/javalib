(*
 *  This file is part of JavaLib
 *  Copyright (c)2004 Nicolas Cannasse
 *  Copyright (c)2007-2008 Université de Rennes 1 / CNRS
 *  Tiphaine Turpin <first.last@irisa.fr>
 *  Laurent Hubert <first.last@irisa.fr>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)

open JClassLow
open IO.BigEndian
open ExtList
open ExtString
include JBasics

type tmp_constant =
	| ConstantClass of int
	| ConstantField of int * int
	| ConstantMethod of int * int
	| ConstantInterfaceMethod of int * int
	| ConstantString of int
	| ConstantInt of int32
	| ConstantFloat of float
	| ConstantLong of int64
	| ConstantDouble of float
	| ConstantNameAndType of int * int
	| ConstantStringUTF8 of string
	| ConstantUnusable

let parse_constant max ch =
  let cid = IO.read_byte ch in
  let index() =
    let n = read_ui16 ch in
      if n = 0 || n >= max
      then raise (Illegal_value (string_of_int n, "index in constant pool"));
      n
  in
    match cid with
      | 7 ->
	  ConstantClass (index())
      | 9 ->
	  let n1 = index() in
	  let n2 = index() in
	    ConstantField (n1,n2)
      | 10 ->
	  let n1 = index() in
	  let n2 = index() in
	    ConstantMethod (n1,n2)
      | 11 ->
	  let n1 = index() in
	  let n2 = index() in
	    ConstantInterfaceMethod (n1,n2)
      | 8 ->
	  ConstantString (index())
      | 3 ->
	  ConstantInt (read_real_i32 ch)
      | 4 ->
	  let f = Int32.float_of_bits (read_real_i32 ch) in
	    ConstantFloat f
      | 5 ->
	  ConstantLong (read_i64 ch)
      | 6 ->
	  ConstantDouble (read_double ch)
      | 12 ->
	  let n1 = index() in
	  let n2 = index() in
	    ConstantNameAndType (n1,n2)
      | 1 ->
	  let len = read_ui16 ch in
	  let str = IO.nread ch len in
	    ConstantStringUTF8 str
      | cid ->
	  raise (Illegal_value (string_of_int cid, "constant kind"))

let class_flags =
  [|`AccPublic; `AccRFU 0x2; `AccRFU 0x4; `AccRFU 0x8;
   `AccFinal; `AccSuper; `AccRFU 0x40; `AccRFU 0x80;
   `AccRFU 0x100; `AccInterface; `AccAbstract; `AccRFU 0x800;
   `AccSynthetic; `AccAnnotation; `AccEnum; `AccRFU 0x8000|]
let innerclass_flags =
  [|`AccPublic; `AccPrivate; `AccProtected; `AccStatic;
   `AccFinal; `AccRFU 0x20; `AccRFU 0x40; `AccRFU 0x80;
   `AccRFU 0x100; `AccInterface; `AccAbstract; `AccRFU 0x800;
   `AccSynthetic; `AccAnnotation; `AccEnum; `AccRFU 0x8000|]
let field_flags =
  [|`AccPublic; `AccPrivate; `AccProtected; `AccStatic;
   `AccFinal; `AccRFU 0x20; `AccVolatile; `AccTransient;
   `AccRFU 0x100; `AccRFU 0x200; `AccRFU 0x400; `AccRFU 0x800;
   `AccSynthetic; `AccRFU 0x2000; `AccEnum; `AccRFU 0x8000|]
let method_flags =
  [|`AccPublic; `AccPrivate; `AccProtected; `AccStatic;
   `AccFinal; `AccSynchronized; `AccBridge; `AccVarArgs;
   `AccNative; `AccRFU 0x200; `AccAbstract; `AccStrict;
   `AccSynthetic; `AccRFU 0x2000; `AccRFU 0x4000; `AccRFU 0x8000|]

let parse_access_flags all_flags ch =
	let fl = read_ui16 ch in
	let flags = ref [] in
	  Array.iteri
	    (fun i f -> if fl land (1 lsl i) <> 0 then flags := f :: !flags)
	    all_flags;
	!flags

(* Validate an utf8 string and return a stream of characters. *)
let read_utf8 s =
  UTF8.validate s;
  let index = ref 0 in
    Stream.from
      (function _ ->
	 if UTF8.out_of_range s ! index
	 then None
	 else
	   let c = UTF8.look s ! index in
	     index := UTF8.next s ! index;
	     Some c)

(* Java ident, with unicode letter and numbers, starting with a letter. *)
let rec parse_ident buff = parser
  | [< 'c when c <> UChar.of_char ';'
	 && c <> UChar.of_char '/'; (* should be a letter *)
       name =
	 (UTF8.Buf.add_char buff c;
	  parse_more_ident buff) >] -> name

and parse_more_ident buff = parser
  | [< 'c when c <> UChar.of_char ';'
	 && c <> UChar.of_char '/'; (* should be a letter or a number *)
       name =
	 (UTF8.Buf.add_char buff c;
	  parse_more_ident buff) >] -> name
  | [< >] ->
      UTF8.Buf.contents buff

(* Qualified name (internally encoded with '/'). *)
let rec parse_name = parser
  | [< ident = parse_ident (UTF8.Buf.create 0);
       name = parse_more_name >] -> ident :: name

and parse_more_name = parser
  | [< 'slash when slash = UChar.of_char '/';
       name = parse_name >] -> name
  | [< >] -> []

(* Java type. *)
let parse_basic_type = parser
  | [< 'b when b = UChar.of_char 'B' >] -> `Byte
  | [< 'c when c = UChar.of_char 'C' >] -> `Char
  | [< 'd when d = UChar.of_char 'D' >] -> `Double
  | [< 'f when f = UChar.of_char 'F' >] -> `Float
  | [< 'i when i = UChar.of_char 'I' >] -> `Int
  | [< 'j when j = UChar.of_char 'J' >] -> `Long
  | [< 's when s = UChar.of_char 'S' >] -> `Short
  | [< 'z when z = UChar.of_char 'Z' >] -> `Bool

let rec parse_object_type = parser
  | [< 'l when l = UChar.of_char 'L';
       name = parse_name;
       'semicolon when semicolon = UChar.of_char ';' >] -> TClass name

  | [< a = parse_array >] -> a

and parse_type = parser
  | [< b = parse_basic_type >] -> TBasic b
  | [< o = parse_object_type >] -> TObject o

(* Java array type. *)
and parse_array = parser
  | [< 'lbracket when lbracket = UChar.of_char '['; typ = parse_type >] ->
      TArray typ

let rec parse_types = parser
  | [< typ = parse_type ; types = parse_types >] -> typ :: types
  | [< >] -> []

let parse_type_option = parser
  | [< typ = parse_type >] -> Some typ
  | [< >] -> None

(* A class name, possibly an array class. *)
let parse_ot = parser
  | [< array = parse_array >] -> array
  | [< name = parse_name >] -> TClass name

let parse_method_sig = parser
  | [< 'lpar when lpar = UChar.of_char '(';
       types = parse_types;
       'rpar when rpar = UChar.of_char ')';
       typ = parse_type_option >] ->
      (types, typ)

(* Java signature. *)
let rec parse_sig = parser
    (* We cannot delete that because of "NameAndType" constants. *)
  | [< typ = parse_type >] -> SValue typ
  | [< sign = parse_method_sig >] -> SMethod sign

let parse_objectType s =
  try
    parse_ot (read_utf8 s)
  with
      Stream.Failure -> raise (Illegal_value (s, "object type"))

let parse_type s =
  try
    parse_type (read_utf8 s)
  with
      Stream.Failure -> raise (Illegal_value (s, "type"))

let parse_method_signature s =
  try
    parse_method_sig (read_utf8 s)
  with
      Stream.Failure -> raise (Illegal_value (s, "method signature"))

let parse_signature s =
  try
    parse_sig (read_utf8 s)
  with
      Stream.Failure -> raise (Illegal_value (s, "signature"))

let parse_stackmap_frame consts ch =
  let parse_type_info ch = match IO.read_byte ch with
    | 0 -> VTop
    | 1 -> VInteger
    | 2 -> VFloat
    | 3 -> VDouble
    | 4 -> VLong
    | 5 -> VNull
    | 6 -> VUninitializedThis
    | 7 -> VObject (get_object_type consts (read_ui16 ch))
    | 8 -> VUninitialized (read_ui16 ch)
    | n -> raise (Illegal_value (string_of_int n, "stackmap type"))
  in let parse_type_info_array ch nb_item =
      List.init nb_item (fun _ ->parse_type_info ch)
  in let offset = read_ui16 ch in
  let number_of_locals = read_ui16 ch in
  let locals = parse_type_info_array ch number_of_locals in
  let number_of_stack_items = read_ui16 ch in
  let stack = parse_type_info_array ch number_of_stack_items in
    (offset,locals,stack)

let rec parse_code consts ch =
	let max_stack = read_ui16 ch in
	let max_locals = read_ui16 ch in
	let clen = read_i32 ch in
	let code =
	    JCode.parse_code ch clen
	in
	let exc_tbl_length = read_ui16 ch in
	let exc_tbl = List.init exc_tbl_length (fun _ ->
		let spc = read_ui16 ch in
		let epc = read_ui16 ch in
		let hpc = read_ui16 ch in
		let ct =
		  match read_ui16 ch with
		    | 0 -> None
		    | ct ->
			match get_constant consts ct with
			  | ConstValue (ConstClass (TClass c)) -> Some c
			  | _ -> raise (Illegal_value ("", "class index"))
		in
		{
			e_start = spc;
			e_end = epc;
			e_handler = hpc;
			e_catch_type = ct;
		}
	) in
	let attrib_count = read_ui16 ch in
	let attribs =
	  List.init
	    attrib_count
	    (fun _ -> parse_attribute [`LineNumberTable ; `LocalVariableTable ; `StackMap] consts ch) in
	{
		c_max_stack = max_stack;
		c_max_locals = max_locals;
		c_exc_tbl = exc_tbl;
		c_attributes = attribs;
		c_code = code;
	}

(* Parse an attribute, if its name is in list. *)
and parse_attribute list consts ch =
	let aname = get_string_ui16 consts ch in
	let error() = raise (Parse_error ("Malformed attribute " ^ aname)) in
	let alen = read_i32 ch in
	let check name =
	  if List.mem name list
	  then ()
	  else raise Exit
	in
	  try
	match aname with
	| "SourceFile" -> check `SourceFile;
		if alen <> 2 then error();
		AttributeSourceFile (get_string_ui16 consts ch)
	| "ConstantValue" -> check `ConstantValue;
	    if alen <> 2 then error();
	    AttributeConstant (get_constant_value consts (read_ui16 ch))
	| "Code" -> check `Code;
	    let ch, count = IO.pos_in ch in
	    let code = parse_code consts ch in
	      if count() <> alen then error();
	      AttributeCode code
	| "Exceptions" -> check `Exceptions;
	    let nentry = read_ui16 ch in
	      if nentry * 2 + 2 <> alen then error();
	      AttributeExceptions
		(List.init
		   nentry
		   (function _ ->
		      get_class_ui16 consts ch))
	| "InnerClasses" -> check `InnerClasses;
	    let nentry = read_ui16 ch in
	      if nentry * 8 + 2 <> alen then error();
	      AttributeInnerClasses
		(List.init
		   nentry
		   (function _ ->
		      let inner =
			match (read_ui16 ch) with
			  | 0 -> None
			  | i -> Some (get_class consts i) in
		      let outer =
			match (read_ui16 ch) with
			  | 0 -> None
			  | i -> Some (get_class consts i) in
		      let inner_name =
			match (read_ui16 ch) with
			  | 0 -> None
			  | i -> Some (get_string consts i) in
		      let flags = parse_access_flags innerclass_flags ch in
			inner, outer, inner_name, flags))
	| "Synthetic" -> check `Synthetic;
	    if alen <> 0 then error ();
	    AttributeSynthetic
	| "LineNumberTable" -> check `LineNumberTable;
	    let nentry = read_ui16 ch in
	      if nentry * 4 + 2 <> alen then error();
	      AttributeLineNumberTable
		(List.init
		   nentry
		   (fun _ ->
		      let pc = read_ui16 ch in
		      let line = read_ui16 ch in
			pc , line))
	| "LocalVariableTable" -> check `LocalVariableTable;
	    let nentry = read_ui16 ch in
	      if nentry * 10 + 2 <> alen then error();
	      AttributeLocalVariableTable
		(List.init
		   nentry
		   (function _ ->
		      let start_pc = read_ui16 ch in
		      let length = read_ui16 ch in
		      let name = (get_string_ui16 consts ch) in
		      let signature = parse_type (get_string_ui16 consts ch) in
		      let index = read_ui16 ch in
			start_pc, length, name, signature, index))
	| "Deprecated" -> check `Deprecated;
	    if alen <> 0 then error ();
	    AttributeDeprecated
	| "StackMap" -> check `StackMap;
	    let ch, count = IO.pos_in ch in
	    let nb_stackmap_frames = read_ui16 ch in
	    let stackmap =
	      List.init nb_stackmap_frames (fun _ -> parse_stackmap_frame consts ch )
	    in
	      if count() <> alen then error();
	      AttributeStackMap stackmap
	| _ -> raise Exit
	  with
	      Exit -> AttributeUnknown (aname,IO.nread ch alen)

let parse_field consts ch =
	let acc = parse_access_flags field_flags ch in
	let name = get_string_ui16 consts ch in
	let sign = parse_type (get_string_ui16 consts ch) in
	let attrib_count = read_ui16 ch in
	let attrib_to_parse =
	  if List.exists ((=)`AccStatic) acc
	  then  [`ConstantValue ; `Synthetic ; `Deprecated]
	  else  [`Synthetic ; `Deprecated] in
	let attribs =
	  List.init
	    attrib_count
	    (fun _ -> parse_attribute attrib_to_parse consts ch) in
	{
		f_name = name;
		f_descriptor = sign;
		f_attributes = attribs;
		f_flags = acc;
	}

let parse_method consts ch =
	let acc = parse_access_flags method_flags ch in
	let name = get_string_ui16 consts ch in
	let sign = parse_method_signature (get_string_ui16 consts ch) in
	let attrib_count = read_ui16 ch in
	let attribs = List.init attrib_count
	  (fun _ ->
	     parse_attribute [`Code ; `Exceptions ; `Synthetic ; `Deprecated] consts ch)
	in
	{
		m_name = name;
		m_descriptor = sign;
		m_attributes = attribs;
		m_flags = acc;
	}

let rec expand_constant consts n =
  let expand name cl nt =
    match expand_constant consts cl  with
      | ConstValue (ConstClass c) ->
	  (match expand_constant consts nt with
	     | ConstNameAndType (n,s) -> (c,n,s)
	     | _ -> raise (Illegal_value ("", "NameAndType in " ^ name ^ " constant")))
      | _ -> raise (Illegal_value ("", "Class in " ^ name ^ " constant"))
  in
	match consts.(n) with
	| ConstantClass i ->
	    (match expand_constant consts i with
	       | ConstStringUTF8 s -> ConstValue (ConstClass (parse_objectType s))
	       | _ -> raise (Illegal_value ("", "string in Class constant")))
	| ConstantField (cl,nt) ->
	    (match expand "Field" cl nt with
	       | TClass c, n, SValue v -> ConstField (c, n, v)
	       | TClass _, _, _ -> raise (Illegal_value ("", "type in Field constant"))
	       | _ -> raise (Illegal_value ("", "class in Field constant")))
	| ConstantMethod (cl,nt) ->
	    (match expand "Method" cl nt with
	       | c, n, SMethod v -> ConstMethod (c, n, v)
	       | _, _, SValue _ -> raise (Illegal_value ("", "type in Method constant")))
	| ConstantInterfaceMethod (cl,nt) ->
	    (match expand "InterfaceMethod" cl nt with
	       | TClass c, n, SMethod v -> ConstInterfaceMethod (c, n, v)
	       | TClass _, _, _ -> raise (Illegal_value ("", "type in Interface Method constant"))
	       | _, _, _ -> raise (Illegal_value ("", "class in Interface Method constant")))
	| ConstantString i ->
		(match expand_constant consts i with
		| ConstStringUTF8 s -> ConstValue (ConstString s)
		| _ -> raise (Illegal_value ("", "String constant")))
	| ConstantInt i -> ConstValue (ConstInt i)
	| ConstantFloat f -> ConstValue (ConstFloat f)
	| ConstantLong l -> ConstValue (ConstLong l)
	| ConstantDouble f -> ConstValue (ConstDouble f)
	| ConstantNameAndType (n,t) ->
		(match expand_constant consts n , expand_constant consts t with
		| ConstStringUTF8 n , ConstStringUTF8 t -> ConstNameAndType (n,parse_signature t)
		| ConstStringUTF8 _ , _ ->
		    raise (Illegal_value ("", "type in NameAndType constant"))
		| _ -> raise (Illegal_value ("", "name in NameAndType constant")))
	| ConstantStringUTF8 s -> ConstStringUTF8 s
	| ConstantUnusable -> ConstUnusable

let parse_class_low_level ch =
	let magic = read_real_i32 ch in
	if magic <> 0xCAFEBABEl then raise (Parse_error "invalid magic number");
	let _version_minor = read_ui16 ch in
	let _version_major = read_ui16 ch in
	let constant_count = read_ui16 ch in
	let const_big = ref true in
	let consts = Array.init constant_count (fun _ ->
		if !const_big then begin
			const_big := false;
			ConstantUnusable
		end else
			let c = parse_constant constant_count ch in
			(match c with ConstantLong _ | ConstantDouble _ -> const_big := true | _ -> ());
			c
	) in
	let consts = Array.mapi (fun i _ -> expand_constant consts i) consts in
	let flags = parse_access_flags class_flags ch in
	let this = get_class_ui16 consts ch in
	let super_idx = read_ui16 ch in
	let super = if super_idx = 0 then None else Some (get_class consts super_idx) in
	let interface_count = read_ui16 ch in
	let interfaces = List.init interface_count (fun _ -> get_class_ui16 consts ch) in
	let field_count = read_ui16 ch in
	let fields = List.init field_count (fun _ -> parse_field consts ch) in
	let method_count = read_ui16 ch in
	let methods = List.init method_count (fun _ -> parse_method consts ch) in
	let attrib_count = read_ui16 ch in
	let attribs =
	  List.init
	    attrib_count
	    (fun _ -> parse_attribute [`SourceFile ; `Deprecated;`InnerClasses] consts ch) in
	{
		j_consts = consts;
		j_flags = flags;
		j_name = this;
		j_super = super;
		j_interfaces = interfaces;
		j_fields = fields;
		j_methods = methods;
		j_attributes = attribs;
	}

let parse_class ch = JLow2High.low2high_class (parse_class_low_level ch)
