(*
 *  This file is part of JavaLib
 *  Copyright (c)2007 Université de Rennes 1 / CNRS
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

open JDumpBasics
open JBasics
open JClass
open Format

open JPrint
open JProgram

let get_hierachy prog info : info =
  let ppclassmap cn2link fmt cm =
    let first = ref true in
    let ppcn fmt cn =
      fprintf fmt "%a" (cn2link cn) (class_name cn)
    in
      ClassMap.iter 
	(fun cn _ -> 
	  if !first && info.f_class cn then 
	    (ppcn fmt cn; first := false)
	  else if info.f_class cn then
	    fprintf fmt ",@ %a" ppcn cn)
	cm
  in
    {info with
      p_class = (fun cn fmt ->
	let c = get_interface_or_class prog cn in
	  match c with
	    | `Class c ->
		fprintf fmt "@[%t@[<hv 2>Direct subclasses: {@{<hierarchy>@,%a@}}@]@]@,"
		  (info.p_class cn) (ppclassmap cn2link) c.c_children
	    | `Interface c ->
		fprintf fmt "@[%t@[<hv 2>Direct implementations:@ {@{<hierarchy>%a@}}@],"
		  (info.p_class cn) (ppclassmap cn2link) c.i_children_class ;
		fprintf fmt "@ @[<hv 2>Direct subinterfaces: {@{<hierarchy>@,%a@}}@]@]@,"
		  (ppclassmap cn2link) c.i_children_interface);

      p_method = (fun cn ms fmt ->
	let ioc = get_interface_or_class prog cn in
	let m = get_method ioc ms in
	let get_overreridden_in = function
	  | AbstractMethod am -> List.map (fun c -> c.i_name) am.am_overridden_in
	  | ConcreteMethod cm -> List.map (fun c -> c.c_name) cm.cm_overridden_in
	and get_implemented_in = function
	  | AbstractMethod am -> List.map (fun c -> c.c_name) am.am_implemented_in
	  | ConcreteMethod _ -> raise (Invalid_argument "get_implemented_in")
	and ppcnl fmt cnl =
	  pp_concat
	    (fun cn -> ms2link (cn,ms) fmt (class_name cn))
	    (fun _ -> fprintf fmt "@{<hierarchy>@,")
	    (fun _ -> fprintf fmt "@}")
	    (fun _ -> fprintf fmt ";@ ")
	    cnl
	in
	let pp_overrides fmt =
	  if ms.ms_name = "<init>" || ms.ms_name = "<clinit>"
	  then ()
	  else
	    match ioc with
	      | `Interface _ -> ()
	      | `Class c ->
		  try
		    match c.c_super_class with
		      | None -> ()
		      | Some c ->
			  let c' = JControlFlow.resolve_method' ms c in
			    fprintf fmt "@[<hv 2>Overrides the method in: {@{<hierarchy>@,%a@}}@]@,"
			      (fun fmt cn -> ms2link (cn,ms) fmt (class_name cn)) (c'.c_name)
		  with NoSuchMethodError -> ()
	in
	let pp_implements fmt =
	  let s = 
	    match ioc with
	      | `Class _ -> "Implements"
	      | `Interface _ -> "Overrides"
	  in
	    fprintf fmt "@[<hv 2>%s the methods in: {%a}@]@,"
	      s ppcnl (List.map (fun i -> i.i_name) (JControlFlow.resolve_interface_method' ms ioc))
	in
	let pp_overridden_in fmt =
	  fprintf fmt "@[<hv 2>Overridden in: {@{<hierarchy>@,%a@}}@]@,"
	    ppcnl (get_overreridden_in m);
	  match ioc with
	    | `Class _ -> ()
	    | `Interface _ ->
		fprintf fmt "@[<hv 2>Implemented in: {@{<hierarchy>@,%a@}}@]@,"
		  ppcnl (get_implemented_in m)
	in 
	  fprintf fmt "%t%t%t%t"
	    (info.p_method cn ms) pp_implements pp_overrides pp_overridden_in
      )
    }
