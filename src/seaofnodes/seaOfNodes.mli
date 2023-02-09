module Type = SeaOfNodes__Type
module Translator :
  sig val translate_jopcodes : JCode.jopcodes -> Type.Node.t Type.IMap.t end
module Interpretor :
  sig val eval_data : Type.Data.t -> int end
