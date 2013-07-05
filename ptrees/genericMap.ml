module type S = 
sig 
  type t
end 



module type GenericMapSig =
sig
  type f
  type key = int * f
  type 'a t = (key * 'a) Ptmap.t
  val empty : 'a t
  val is_empty : 'a t -> bool
  val add : key -> 'a -> 'a t -> 'a t
  val modify: key -> ('a option -> 'a) -> 'a t -> 'a t
  val find : key -> 'a t -> 'a
  val remove : key -> 'a t -> 'a t
  val mem : key -> 'a t -> bool
  val iter : (key -> 'a -> unit) -> 'a t -> unit
  val map : ('a -> 'b) -> 'a t -> 'b t
  val mapi : (key -> 'a -> 'b) -> 'a t -> 'b t
  val fold : (key -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
  val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int
  val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool
  val merge : ('a -> 'a -> 'a) -> 'a t -> 'a t -> 'a t
    (** [merge f m1 m2] returns a map that has the bindings of [m1] and [m2] and
        which binds [k] to [f d1 d2] if [m1] and [m2] binds the same [k] to
        different [d1] and [d2], respectively. If [d1] equals [d2], [f d1 d2] is
        supposed to return [d1]. *)
  val choose_and_remove : 'a t -> key * 'a * 'a t
    (** [choose_and_remove t] returns (i,d,t') such that [t'] equals to [remove
        i t] and [d] equals to [find i t].

        @raise Not_found if [t] is empty. *)
  val filter : ('a -> bool) -> 'a t -> 'a t
  val filteri : (key -> 'a -> bool) -> 'a t -> 'a t
  val key_elements : 'a t -> key list
  val value_elements : 'a t -> 'a list
  val elements : 'a t -> (key * 'a) list
end


module Make ( S : sig type t end ) =
struct
  type f = S.t
  type key = int * f
  type 'a t = (key * 'a) Ptmap.t

  let empty = Ptmap.empty
  let is_empty = Ptmap.is_empty
  let add key o m = Ptmap.add (fst key) (key, o) m
  let modify key f m = Ptmap.modify (fst key)
    (fun x -> match x with
       | None -> (key, f None)
       | Some (_,a) -> (key, f (Some a))
    ) m
  let find key m = snd (Ptmap.find (fst key) m)
  let remove key m = Ptmap.remove (fst key) m
  let mem key m = Ptmap.mem (fst key) m
  let iter f m = Ptmap.iter (fun _ (k,d) -> f k d) m
  let map f m = Ptmap.map (fun (k,d) -> (k, f d)) m
  let mapi f m = Ptmap.mapi (fun _ (k,d) -> (k, f k d)) m
  let fold f m e = Ptmap.fold (fun _ (k,d) -> f k d) m e
  let compare f m1 m2 = Ptmap.compare (fun a b -> f (snd a) (snd b)) m1 m2
  let equal f m1 m2 = Ptmap.equal (fun a b -> f (snd a) (snd b)) m1 m2
  let merge f m1 m2 = Ptmap.merge (fun a b -> (fst a), f (snd a) (snd b)) m1 m2
  let choose_and_remove m =
    let (_,(k,d),m) = Ptmap.choose_and_remove m in
      (k, d, m)
  let filter f m =
    Ptmap.filter (fun (_,d) -> f d) m
  let filteri f m =
    Ptmap.filter (fun (k,d) -> f k d) m
  let key_elements m =
    Ptmap.fold (fun _ (k,_) l -> k :: l) m []
  let value_elements m =
    Ptmap.fold (fun _ (_,b) l -> b :: l) m []
  let elements m =
    Ptmap.fold (fun _ e l -> e :: l) m []
end
