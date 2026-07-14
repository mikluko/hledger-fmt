module Main (main) where

import Data.ByteString.Lazy.Char8 qualified as LC8
import System.FilePath ((<.>), (</>))
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

import Hledger.Fmt (format, formatSorted, isFormatted, isFormattedSorted)

-- | Fixtures live as @<name>.in.ledger@ (raw input) and @<name>.golden@
-- (expected formatted output) under @test/testdata@.
fixtures :: [String]
fixtures = ["postings", "directives", "trailing", "multi", "assertion"]

-- | Sort fixtures live as @<name>.in.ledger@ and @<name>.sorted.golden@
-- (expected @--sort@ output).
sortFixtures :: [String]
sortFixtures = ["sort"]

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
            , sortTests
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

-- | @--sort@ reproduces the sorted golden, is idempotent, and @--check --sort@
-- accepts the sorted golden.
sortTests :: TestTree
sortTests =
    testGroup "sort" $
        [ goldenVsString name (testdata </> name <.> "sorted" <.> "golden") $
            LC8.pack . formatSorted <$> readIn name
        | name <- sortFixtures
        ]
            ++ [ testCase (name <> ": idempotent") $ do
                    g <- readFile (testdata </> name <.> "sorted" <.> "golden")
                    formatSorted g @?= g
               | name <- sortFixtures
               ]
            ++ [ testCase (name <> ": sorted golden passes --check --sort") $ do
                    g <- readFile (testdata </> name <.> "sorted" <.> "golden")
                    isFormattedSorted g @?= True
               | name <- sortFixtures
               ]
