open JClass

let list sep = function
  | t :: q ->
      List.fold_left
	(fun p s -> p ^ sep ^ s)
	t
	q
  | [] -> ""

let print_ident = list "."

let replace_dot s =
  let s = String.copy s in
    for i = 0 to String.length s - 1 do
      if s.[i] = '.' then s.[i] <- '/'
    done;
    s

(* [mkdir -p] *)
let rec mkdir d perms =
  if d <> Filename.current_dir_name
  then (
    mkdir (Filename.dirname d) perms;
    try
      Unix.mkdir d perms
    with Unix.Unix_error _ -> ()
  )

(* We should catch only the exceptions Unix_error _ and End_of_file
   that we raised. *)

exception No_class_found of string

(* Try to open a string as a directory and recursively applies f to
   every .class file in it. Throws ENOTDIR or ENOENT otherwise. *)
let rec apply_to_dir f s =
  let rep = Unix.opendir s in
    try
      while true do
	let s' = Unix.readdir rep in
	  if
	    s' <> "." && s' <> ".."
	  then
	    let s = Filename.concat s s' in
	      try apply_to_dir f s
	      with
		  Unix.Unix_error (Unix.ENOTDIR, _, _) ->
		    (if
		       Filename.check_suffix s ".class"
		     then
		       f s)
      done
    with
	End_of_file -> Unix.closedir rep

(* Try to interpret a string as a directory or a class name without the
   .class suffix and applies f to the relevant .class files. Throws
   No_class_found otherwise. *)
let apply_to_dir_or_class f s =
  try
    apply_to_dir f s
  with
      Unix.Unix_error ((Unix.ENOTDIR | Unix.ENOENT), _, _) ->
	let class_file = s ^ ".class" in
	  if
	    try
	      (Unix.stat class_file).Unix.st_kind <> Unix.S_DIR
	    with
		Unix.Unix_error (Unix.ENOENT, _, _) -> false
	  then
	    f (class_file)
	  else
	    raise (No_class_found s)

(* Try to open a jar file, checking for the .jar suffix. f is applied to
   all .class files in the archive. other is applied to other files.
   Throws No_class_found otherwise. *)
let apply_to_jar f other s =
  if
    Filename.check_suffix s ".jar"
    &&
      try
	(Unix.stat s).Unix.st_kind <> Unix.S_DIR
      with
	  Unix.Unix_error (Unix.ENOENT, _, _) -> false
  then
    let jar = Zip.open_in s in
      List.iter
	(function e ->
	   if Filename.check_suffix e.Zip.filename ".class"
	   then (
	     let input = IO.input_string (Zip.read_entry jar e) in
	     let c = JParse.parse_class input in
	       IO.close_in input;
	       f c
	   ) else other jar e)
	(Zip.entries jar);
      Zip.close_in jar
  else
    raise (No_class_found s)

(* Try to read or transform a set of classes given by a string. The
   name is interpreted (in order of priority) as:
   - a directory name
   - a class name (without extension)
   - a jar file (with the .jar suffix).
   The resulting directory, class file, or jar file if any, is written
   in the directory given as argument of the `transform constructor.
   Throws No_class_found otherwise. *)
let fold class_path f file =
  if not (Filename.is_implicit file)
  then
    failwith ("invalid class name " ^ file ^ ", must be implicit")
  else
    let c = replace_dot file in
      try
	apply_to_dir_or_class
	  (function c ->
	     let ch = open_in_bin c in
	     let input = IO.input_channel ch in
	     let classe = JParse.parse_class input in
	       IO.close_in input;
	       match f with
		 | `read f ->
		     f classe
		 | `transform (output_dir, f) ->
		     let classe = f classe in
		     let class_name = print_ident classe.j_name in
		     let c = replace_dot class_name ^ ".class" in
		       (mkdir
			  (Filename.concat output_dir (Filename.dirname c))
			  0o755);
		       let f = open_out_bin (Filename.concat output_dir c) in
		       let output = IO.output_channel f in
			 JUnparse.unparse_class output classe;
			 IO.close_out output)
	  (Filename.concat class_path c)
      with
	  No_class_found _ ->
	    match f with
	      | `read f ->
		  apply_to_jar
		    (function classe ->
		       f classe)
		    (fun _ _ -> ())
		    (Filename.concat class_path file)
	      | `transform (output_dir, f) ->
		  mkdir
		    (Filename.concat output_dir (Filename.dirname file))
		    0o755;
		  let jar' = Zip.open_out (Filename.concat output_dir file) in
		    (try
		    apply_to_jar
		      (function classe ->
			 let classe = f classe in
			 let class_name = print_ident classe.j_name in
			 let c = replace_dot class_name ^ ".class"
			 and contents =
			   let s = IO.output_string () in
			     JUnparse.unparse_class s classe;
			     IO.close_out s in
			   Zip.add_entry contents jar' c)
		      (fun jar e ->
			 let contents = Zip.read_entry jar e in
			   Zip.add_entry contents jar' e.Zip.filename)
		      (Filename.concat class_path file);
		     with
			 e ->
			   Zip.close_out jar';
			   Unix.unlink (Filename.concat output_dir file);
			   raise e);
		    Zip.close_out jar'

let rec fold_directories f file = function
  | [] -> raise (No_class_found file)
  | class_path :: q ->
      try fold class_path f file
      with No_class_found _ ->
	fold_directories f file q

(* Applies f to a list of files, in a colon-separated list of directories. *)
let fold class_path f files =
  try
    List.iter
      (function file ->
	 fold_directories f file
	   (match ExtString.String.nsplit class_path ":" with
	      | [] -> [Filename.current_dir_name]
	      | cp -> cp))
      files
  with No_class_found c ->
    failwith ("no class found for " ^ c)

let read class_path f accu files =
  let accu = ref accu in
    fold class_path (`read (function classe -> accu := f ! accu classe)) files;
    ! accu

let transform class_path output_dir f files =
  fold class_path (`transform (output_dir, f)) files
