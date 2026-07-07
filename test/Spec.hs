module Main (main) where

import Data.ByteString.Lazy.Char8 qualified as LC8
import System.FilePath ((<.>), (</>))
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

import Hledger.Fmt (format, isFormatted)

-- | Fixtures live as @<name>.in.ledger@ (raw input) and @<name>.golden@
-- (expected formatted output) under @test/testdata@.
fixtures :: [String]
fixtures = ["postings", "directives", "trailing", "multi", "assertion"]

testdata :: FilePath
testdata = "test" </> "testdata"

main :: IO ()
main =
    defaultMain $
        testGroup
            "hledger-fmt"
            [ goldenTests
            , idempotenceTests
            , checkTests
            ]

readIn :: String -> IO String
readIn name = readFile (testdata </> name <.> "in" <.> "ledger")

readGolden :: String -> IO String
readGolden name = readFile (testdata </> name <.> "golden")

-- | Formatting the raw input must reproduce the golden output byte-for-byte.
goldenTests :: TestTree
goldenTests =
    testGroup "golden" $
        [ goldenVsString name (testdata </> name <.> "golden") $
            LC8.pack . format <$> readIn name
        | name <- fixtures
        ]

-- | Formatting an already-formatted file is a no-op.
idempotenceTests :: TestTree
idempotenceTests =
    testGroup "idempotence" $
        [ testCase name $ do
            g <- readGolden name
            format g @?= g
        | name <- fixtures
        ]

-- | @--check@ accepts the golden output and rejects any raw input that is not
-- already in golden form.
checkTests :: TestTree
checkTests =
    testGroup "check" $
        concat
            [ [ testCase (name <> ": golden is formatted") $ do
                    g <- readGolden name
                    isFormatted g @?= True
              , testCase (name <> ": raw input differs when unformatted") $ do
                    raw <- readIn name
                    g <- readGolden name
                    isFormatted raw @?= (raw == g)
              ]
            | name <- fixtures
            ]
