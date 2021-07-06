||| Copyright (c) 2020 Edwin Brady
|||     School of Computer Science, University of St Andrews
||| All rights reserved.

||| This code is derived from software written by Edwin Brady
||| (ecb10@st-andrews.ac.uk).

||| I (Chiyoku) just modified the parser to include custom errors.

module Modified.Parser

import Data.Bool
import Data.List
import Data.List1
import Data.Nat
import Data.Vect

import public Modified.Core
import public Text.Quantity
import public Text.Token

||| Parse a terminal based on a kind of token.
export
match : (Eq k, TokenKind k) =>
        (kind : k) ->
        Grammar err  (Token k) True (TokType kind)
match kind = terminal (const UnrecognizedInput) $
  \(Tok kind' text) => if kind' == kind
                          then Just $ tokValue kind text
                          else Nothing

||| Optionally parse a thing, with a default value if the grammar doesn't
||| match. May match the empty input.
export
option : {c : Bool} ->
         (def : a) -> (p : Grammar err  tok c a) ->
         Grammar err  tok False a
option {c = False} def p = p <|> pure def
option {c = True} def p = p <|> pure def

||| Optionally parse a thing.
||| To provide a default value, use `option` instead.
export
optional : {c : _} ->
           (p : Grammar err  tok c a) ->
           Grammar err  tok False (Maybe a)
optional p = option Nothing (map Just p)

||| Try to parse one thing or the other, producing a value that indicates
||| which option succeeded. If both would succeed, the left option
||| takes priority.
export
choose : {c1, c2 : _} ->
         (l : Grammar err  tok c1 a) ->
         (r : Grammar err  tok c2 b) ->
         Grammar err  tok (c1 && c2) (Either a b)
choose l r = map Left l <|> map Right r

||| Produce a grammar by applying a function to each element of a container,
||| then try each resulting grammar until the first one succeeds. Fails if the
||| container is empty.
export
choiceMap : {c : Bool} ->
            (a -> Grammar err  tok c b) ->
            Foldable t => t a ->
            Grammar err  tok c b
choiceMap f xs = foldr (\x, acc => rewrite sym (andSameNeutral c) in
                                           f x <|> acc)
                       (fail NoMoreOptions) xs

%hide Prelude.(>>=)

||| Try each grammar in a container until the first one succeeds.
||| Fails if the container is empty.
export
choice : {c : _} ->
         Foldable t => t (Grammar err  tok c a) ->
         Grammar err  tok c a
choice = Parser.choiceMap id

mutual
  ||| Parse one or more things
  export
  some : Grammar err  tok True a ->
         Grammar err  tok True (List1 a)
  some p = pure (!p ::: !(many p))

  ||| Parse zero or more things (may match the empty input)
  export
  many : Grammar err  tok True a ->
         Grammar err  tok False (List a)
  many p = option [] (forget <$> some p)

||| Parse one or more instances of `p`, returning the parsed items and proof
||| that the resulting list is non-empty.
export
some' : (p : Grammar err  tok True a) ->
        Grammar err  tok True (xs : List a ** NonEmpty xs)
some' p = pure (!p :: !(many p) ** IsNonEmpty)

mutual
  private
  count1 : (q : Quantity) ->
           (p : Grammar err  tok True a) ->
           Grammar err  tok True (List a)
  count1 q p = do x <- p
                  seq (count q p)
                      (\xs => pure (x :: xs))

  ||| Parse `p`, repeated as specified by `q`, returning the list of values.
  export
  count : (q : Quantity) ->
          (p : Grammar err  tok True a) ->
          Grammar err  tok (isSucc (min q)) (List a)
  count (Qty Z Nothing) p = many p
  count (Qty Z (Just Z)) _ = pure []
  count (Qty Z (Just (S max))) p = option [] $ count1 (atMost max) p
  count (Qty (S min) Nothing) p = count1 (atLeast min) p
  count (Qty (S min) (Just Z)) _ = fail QuantityOutOfOrder
  count (Qty (S min) (Just (S max))) p = count1 (between min max) p

||| Parse `p` `n` times, returning the vector of values.
export
countExactly : (n : Nat) ->
               (p : Grammar err  tok True a) ->
               Grammar err  tok (isSucc n) (Vect n a)
countExactly Z p = Empty []
countExactly (S k) p = [| p :: countExactly k p |]

mutual
  ||| Parse one or more instances of `p` until `end` succeeds, returning the
  ||| list of values from `p`. Guaranteed to consume input.
  export
  someTill : {c : Bool} ->
             (end : Grammar err  tok c e) ->
             (p : Grammar err  tok True a) ->
             Grammar err  tok True (List1 a)
  someTill {c} end p = do x <- p
                          seq (manyTill end p)
                              (\xs => pure (x ::: xs))

  ||| Parse zero or more instances of `p` until `end` succeeds, returning the
  ||| list of values from `p`. Guaranteed to consume input if `end` consumes.
  export
  manyTill : {c : Bool} ->
             (end : Grammar err  tok c e) ->
             (p : Grammar err  tok True a) ->
             Grammar err  tok c (List a)
  manyTill {c} end p = rewrite sym (andTrueNeutral c) in
                               map (const []) end <|> (forget <$> someTill end p)

mutual
  ||| Parse one or more instance of `skip` until `p` is encountered,
  ||| returning its value.
  export
  afterSome : {c : Bool} ->
              (skip : Grammar err  tok True s) ->
              (p : Grammar err  tok c a) ->
              Grammar err  tok True a
  afterSome skip p = do ignore skip
                        afterMany skip p

  ||| Parse zero or more instance of `skip` until `p` is encountered,
  ||| returning its value.
  export
  afterMany : {c : Bool} ->
              (skip : Grammar err  tok True s) ->
              (p : Grammar err  tok c a) ->
              Grammar err  tok c a
  afterMany {c} skip p = rewrite sym (andTrueNeutral c) in
                                 p <|> afterSome skip p

||| Parse one or more things, each separated by another thing.
export
sepBy1 : {c : Bool} ->
         (sep : Grammar err  tok True s) ->
         (p : Grammar err  tok c a) ->
         Grammar err  tok c (List1 a)
sepBy1 {c} sep p = rewrite sym (orFalseNeutral c) in
                           [| p ::: many (sep *> p) |]

||| Parse zero or more things, each separated by another thing. May
||| match the empty input.
export
sepBy : {c : Bool} ->
        (sep : Grammar err  tok True s) ->
        (p : Grammar err  tok c a) ->
        Grammar err  tok False (List a)
sepBy sep p = option [] $ forget <$> sepBy1 sep p

||| Parse one or more instances of `p` separated by and optionally terminated by
||| `sep`.
export
sepEndBy1 : {c : Bool} ->
            (sep : Grammar err  tok True s) ->
            (p : Grammar err  tok c a) ->
            Grammar err  tok c (List1 a)
sepEndBy1 {c} sep p = rewrite sym (orFalseNeutral c) in
                              sepBy1 sep p <* optional sep

||| Parse zero or more instances of `p`, separated by and optionally terminated
||| by `sep`. Will not match a separator by itself.
export
sepEndBy : {c : Bool} ->
           (sep : Grammar err  tok True s) ->
           (p : Grammar err  tok c a) ->
           Grammar err  tok False (List a)
sepEndBy sep p = option [] $ forget <$> sepEndBy1 sep p

||| Parse one or more instances of `p`, separated and terminated by `sep`.
export
endBy1 : {c : Bool} ->
         (sep : Grammar err  tok True s) ->
         (p : Grammar err  tok c a) ->
         Grammar err  tok True (List1 a)
endBy1 sep p = some $ rewrite sym (orTrueTrue c) in
                              p <* sep

export
endBy : {c : Bool} ->
        (sep : Grammar err  tok True s) ->
        (p : Grammar err  tok c a) ->
        Grammar err  tok False (List a)
endBy sep p = option [] $ forget <$> endBy1 sep p

||| Parse an instance of `p` that is between `left` and `right`.
export
between : {c : _} ->
          (left : Grammar err  tok True l) ->
          (right : Inf (Grammar err  tok True r)) ->
          (p : Inf (Grammar err  tok c a)) ->
          Grammar err  tok True a
between left right contents = left *> contents <* right