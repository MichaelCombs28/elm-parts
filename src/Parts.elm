module Parts exposing 
  ( Update, View
  , Get, Set, embedView, embedUpdate
  , Index, Indexed, indexed
  , Msg
  , pack, update, create, create1, accessors, Accessors
  )

{-| 

Given a TEA component with model type `model` and message type `msg`, we construct
a variant component which knows how to extract its model from a c model
`c` and produces generic messages `Msg c`. The consuming component is assumed
to have message type `obs` (for "observation"). 

# Elm Architecture types
@docs Update, View

# Model embeddings 
@docs Get, Set, embedView, embedUpdate
@docs accessors, Accessors

## Indexed model embeddings
@docs Index, Indexed, indexed

# Message embeddings
@docs Msg, update

# Part construction
@docs create, create1

-}

import Platform.Cmd exposing (Cmd)
import Dict exposing (Dict)


-- TYPES


{-| Standard TEA update function type. 
-}
type alias Update model msg = 
  msg -> model -> (model, Cmd msg)


{-| Standard TEA view function type. 
-}
type alias View model a = 
  model -> a


-- EMBEDDINGS


{-| Type of "getter": fetch component model `m` from c model `c`. 
-}
type alias Get model c =
  c -> model


{-| Type of "setter": update component model `m` in c `c`. 
-}
type alias Set model c = 
  model -> c -> c


{-| Lift a `view` to one which knows how to retrieve its `model` from 
a c model `c`. 
-}
embedView : Get model c -> View model a -> View c a
embedView get view = 
  get >> view 


{-| Lift an `update` from operating on `model` to a c model `c`. 
-}
embedUpdate : 
    Get model c
 -> Set model c
 -> Update model msg
 -> Update c msg
embedUpdate get set update = 
  \msg c -> 
     update msg (get c) |> map1st (flip set c)


-- INDEXED EMBEDDINGS

 
{-| Type of indices. An index is a list of `Int` rather than just an `Int` to 
support nested dynamically constructed elements: Use indices `[0]`, `[1]`, ...
for statically known top-level components, then use `[0,0]`, `[0,1]`, ...
for a dynamically generated list of components. 
-}
type alias Index 
  = List Int
 

{-| Indexed families of things.
-}
type alias Indexed a = 
  Dict Index a 


{-| Fix a getter and setter for an `Indexed model` to a particular `Index`.
-}
indexed : 
    Get (Indexed model) c
 -> Set (Indexed model) c
 -> model
 -> Index
 -> (Get model c, Set model c)
indexed get set model0 idx =  
  ( \c -> Dict.get idx (get c) |> Maybe.withDefault model0
  , \model c -> set (Dict.insert idx model (get c)) c
  )
  

-- EMBEDDING MESSAGES


{-| Similar to how embeddings enable collecting models of different type
in a single model c, we collect messages in a single "master
message" type. Messages exist exclusively to be dispatched by a corresponding
`update` function; we can avoid distinguishing between different types of 
messages by dispatching not the `Msg` itself, but a partially applied update
function `update msg`. 

It's instructive to compare `Msg` to the type of `update` partially applied to 
an actual carried message `m`:

    update : m -> c -> (c, Cmd m)
    (update m) : c -> (c, Cmd m)
-}
type Msg c = 
  Msg (c -> (c, Cmd (Msg c)))


{-| Generic update function for Msg. 
-}
update : (Msg c -> m) -> Msg c -> c -> ( c, Cmd m )  
update fwd (Msg f) c = 
  f c |> map2nd (Cmd.map fwd)
  

-- PARTS


{-| Partially apply an `update` function to a `msg`, producing a generic Msg.
-}
pack : (Update c msg) -> msg -> Msg c 
pack upd msg = 
  Msg (upd msg >> map2nd (Cmd.map (pack upd)))


{-| From `update` and `view` functions, produce a `view` function which (a) 
fetches its model from a `c` model, and (b) dispatches generic `Msg`
messages. 

Its instructive to compare the types of the input `view` and `update` for a 
typical case. Notice that `create` transforms `model` -> `c` and
`Html m` -> `Html (Msg c)`. 

  {- Input -}
  view : (m -> obs) -> model -> List (Attributes m) -> List (Html m) -> Html m
  update : m -> model -> (model, Cmd m)

  {- Output -}
  type alias m' = Msg c
  view : c -> List (Attributes m') -> List (Html m') -> Html m'

Note that the input `view` function is assumed to take a function lifting its
messages. 

-}
create 
  : ((m -> obs) -> View model a)
 -> Update model m
 -> Get (Indexed model) c
 -> Set (Indexed model) c
 -> model 
 -> (Msg c -> obs)
 -> Index
 -> View c a
create view update get0 set0 model0 f idx  = 
  let
    (get, set) = 
      indexed get0 set0 model0 idx

    embeddedUpdate = 
      embedUpdate get set update

    embeddedView = 
      embedView get <| view (pack embeddedUpdate >> f) 
  in
    embeddedView


{-| Like `create`, but for components that are assumed to have only one
instance.
-}
create1
  : ((msg -> obs) -> View model a)
 -> Update model msg
 -> Get model c
 -> Set model c
 -> (Msg c -> obs)
 -> View c a

create1 view update get set f = 
  let
    embeddedUpdate = 
      embedUpdate get set update

    embeddedView = 
      embedView get <| view (pack embeddedUpdate >> f)
  in
    embeddedView


{-| For components where consumers do care about the model of the 
component, use the `accessors` function below to generate suitable, 
well, accessors.
-}
type alias Accessors model c = 
  { get : Get model c
  , set : Set model c
  , map : (model -> model) -> c -> c
  , reset : c -> c
  }


{-| Generate accessors.
-}
accessors 
  : Get (Indexed model) c
 -> Set (Indexed model) c
 -> model 
 -> Index
 -> Accessors model c

accessors get0 set0 model0 idx = 
  let
    (get, set) =
      indexed get0 set0 model0 idx
  in
    { get = get
    , set = set
    , map = \f c -> get c |> f |> flip set c
    , reset = \c -> get0 c |> Dict.remove idx |> (\m -> set0 m c)
    }





-- HELPERS


map1st : (a -> c) -> (a,b) -> (c,b)
map1st f (x,y) = (f x, y)


map2nd : (b -> c) -> (a,b) -> (a,c)
map2nd f (x,y) = (x, f y)


