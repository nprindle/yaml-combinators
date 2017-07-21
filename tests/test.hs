{-# LANGUAGE OverloadedLists, OverloadedStrings #-}
import Data.Yaml.Combinators
import Data.Functor
import Test.Tasty
import Test.Tasty.HUnit
import Data.Aeson hiding (object)
import qualified Data.Text as T
import Data.Monoid
import qualified Data.HashMap.Strict as HM

main = defaultMain tests

tests = testGroup "Data.Yaml.Combinators"
  [ testCase "Expect String, get String" $
      runParser string (String "hi") @?=
        Right "hi"
  , testCase "Expect String, get Number" $
      runParser string (Number 3) @?=
        Left (ParseError 0 $ ExpectedInsteadOf ["String"] (Number 3))
  , testCase "Expect specific String, get another String" $
      runParser (theString "bye") (String "hi") @?=
        Left (ParseError 0 $ ExpectedInsteadOf ["\"bye\""] (String "hi"))
  , testCase "Expect specific String or Number, get another string" $
      runParser (theString "bye" <> void number) (String "hi") @?=
        Left (ParseError 0 $ ExpectedInsteadOf ["\"bye\""] (String "hi"))
  , testCase "Expect an array, get an array" $
      runParser (array string) (Array [String "hi"]) @?=
        Right ["hi"]
  , testCase "Expect an array, get an object" $
      runParser (array string) (Object HM.empty) @?=
        Left (ParseError 0 $ ExpectedInsteadOf ["Array"] (Object []))
  , testCase "Expect an array of Strings, get an array of Numbers" $
      runParser (array string) (Array [Number 3]) @?=
        Left (ParseError 1 $ ExpectedInsteadOf ["String"] (Number 3))
  , testCase "Expect an object, get an object" $
      runParser (object $ field "foo" number) (Object [("foo", Number 1)]) @?=
        Right 1
  , testCase "Validated String, accepts anything" $
      runParser (validate string Right) (String "foo") @?=
        Right "foo"
  , testCase "Validated String, rejects everything" $
      runParser (validate string (const (Left "contrarianism" :: Either String String))) (String "foo") @?=
        Left (ParseError 1 (ExpectedInsteadOf ["contrarianism"] (String "foo")))
  , testCase "Expect an object, get an array" $
      runParser (object $ field "foo" number) (Array []) @?=
        Left (ParseError 0 $ ExpectedInsteadOf ["Object"] (Array []))
  , testCase "Expect an object, get an object missing a field" $
      runParser (object $ field "foo" number *> field "bar" string) (Object [("foo", Number 1)]) @?=
        Left (ParseError 1 $ ExpectedAsPartOf ["field \"bar\""] (Object ([("foo",Number 1.0)])))
  , testCase "Expect an object, get an object with an extra field" $
      runParser (object $ field "foo" number) (Object [("foo", Number 1), ("bar", String "x")]) @?=
        Left (ParseError 1 $ UnexpectedAsPartOf (Object [("bar", String "x")]) (Object [("foo", Number 1), ("bar", String "x")]))
  , testCase "Expect an object, get a field that doesn't match" $
      runParser (object $ field "foo" number) (Object [("foo", String "hi")]) @?=
        Left (ParseError 1 $ ExpectedInsteadOf ["Number"] (String "hi"))
  , testCase "Expect an object with opt field, field present" $
      runParser (object $ optField "foo" number) (Object [("foo", Number 1)]) @?=
        Right (Just 1)
  , testCase "Expect an object with opt field, field absent" $
      runParser (object $ optField "foo" number) (Object []) @?=
        Right Nothing
  , testCase "Expect an object with default field, field present" $
      runParser (object $ defaultField "foo" 7 number) (Object [("foo", Number 16309)]) @?=
        Right 16309
  , testCase "Expect an object with default field, field present" $
      runParser (object $ defaultField "foo" 7 number) (Object []) @?=
        Right 7
  , testCase "Expect an array of number and string, get it" $
      runParser
        (theArray $ (,) <$> element number <*> element string)
        (Array [Number 2, String "hi"])
        @?=
        Right (2, "hi")
  , testCase "Expect an array of number and string, get only number" $
      runParser
        (theArray $ (,) <$> element number <*> element string)
        (Array [Number 2])
        @?=
        Left (ParseError 1 (ExpectedAsPartOf ["at least 2 elements"] (Array [Number 2])))
  , testCase "Expect an array of number and string, get only string" $
      runParser
        (theArray $ (,) <$> element number <*> element string)
        (Array [String "hi"])
        @?=
        Left (ParseError 1 $ ExpectedInsteadOf ["Number"] (String "hi"))
  , testCase "Expect an array of number and string, get them and something else" $
      runParser
        (theArray $ (,) <$> element number <*> element string)
        (Array [Number 2, String "hi", Number 42])
        @?=
        Left (ParseError 1 $ UnexpectedAsPartOf (Number 42) (Array [Number 2.0,String "hi",Number 42]))
  , testCase "Wrong tag" $
      runParser
        ((object (Nothing <$ theField "tag" "Nothing")) <>
         (object (Just <$ theField "tag" "Just" <*> field "value" number)))
        (Object [("tag", String "Nothing"), ("value", Number 3)])
        @?=
        Left (ParseError 1 (UnexpectedAsPartOf
          (Object ([("value",Number 3.0)]))
          (Object ([("tag",String "Nothing"),("value",Number 3.0)]))))
  , testCase "More serious error takes precedence even though it happens later" $
      runParser
        (theArray (element (object (pure ())) *> element number))
        (Array [Object [("foo","bar")], String "baz"])
        @?=
        Left (ParseError 1 (ExpectedInsteadOf ["Number"] (String "baz")))
  , testCase "Prefer the branch with missing data to the branch with mismatched tag" $ do
      let
        p1 = object $ ()
          <$ theField "tag" "one"
          <* field "a" string

        p2 = object $ ()
          <$ theField "tag" "two"

        v = Object [("tag", String "one")]
        expected_result = Left (ParseError 1
          (ExpectedAsPartOf
            ["field \"a\""]
            v
          ))
      runParser p1 v @?= expected_result
      runParser (p1 <> p2) v @?= expected_result
      runParser (p2 <> p1) v @?= expected_result
  , testCase "When a tag is mismatched, all alternatives get collected" $ do
      let
        p1 = object $ ()
          <$ theField "tag" "one"
          <* field "a" string

        p2 = object $ ()
          <$ theField "tag" "two"

        p3 = object $ ()
          <$ theField "foo" "bar"
          <* theField "tag" "three"

        v = Object [("tag", String "xxx"),("garbage",Number 7)]
        expected_result = Left (ParseError 1
          (ExpectedInsteadOf
            ["\"one\"", "\"two\"", "\"three\""]
            (String "xxx")
          ))
      runParser (p1 <> p2 <> p3) v @?= expected_result
  , testCase "Alternatives are only reported once" $ do
      let
        even_str = validate string $ \s ->
          if even (T.length s)
            then Right s
            else Left "even-length string"
      runParser (even_str <> even_str) (String "x")
      @?=
      Left (ParseError 1 (ExpectedInsteadOf ["even-length string"] (String "x")))
  ]
