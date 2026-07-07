-- | @hledger-fmt@: a format-preserving hledger journal formatter.
--
-- @
-- hledger-fmt [--check] [FILE|-]...
-- @
--
-- With file operands, each file is formatted in place. With @--check@,
-- nothing is written and the exit status is non-zero if any file is not
-- already formatted. With @-@ or no operands, stdin is formatted to stdout.
module Main (main) where

import Control.Exception (IOException, try)
import Control.Monad (forM, forM_, unless, when)
import System.Environment (getArgs)
import System.Exit (ExitCode (ExitFailure), exitFailure, exitSuccess, exitWith)
import System.IO (
    BufferMode (BlockBuffering),
    Handle,
    IOMode (ReadMode, WriteMode),
    hClose,
    hGetContents',
    hPutStr,
    hPutStrLn,
    hSetBuffering,
    hSetEncoding,
    openFile,
    stderr,
    stdin,
    stdout,
    utf8,
 )

import Hledger.Fmt (format, isFormatted)

version :: String
version = "hledger-fmt 0.2.0.0"

usage :: String
usage =
    unlines
        [ "hledger-fmt: format-preserving hledger journal formatter"
        , ""
        , "Usage: hledger-fmt [--check] [FILE|-]..."
        , "or:    hledger fmt -- [--check] [FILE|-]..."
        , ""
        , "  FILE...          format each file in place"
        , "  --check FILE...  write nothing; exit non-zero if any file is not"
        , "                   already formatted, listing offenders on stderr"
        , "  -, or no args    format stdin to stdout (--check reports via exit code)"
        , ""
        , "  -h, --help       show this help"
        , "      --version    show version"
        ]

-- | Parsed command line: either a terminal action, or a run request.
data Command
    = Help
    | Version
    | Run Bool [FilePath]

main :: IO ()
main = do
    hSetBuffering stdout (BlockBuffering Nothing)
    mapM_ (`hSetEncoding` utf8) [stdin, stdout, stderr]
    args <- getArgs
    case parseArgs args of
        Left err -> do
            hPutStrLn stderr err
            hPutStr stderr usage
            exitWith (ExitFailure 2)
        Right Help -> putStr usage
        Right Version -> putStrLn version
        Right (Run check files) -> case files of
            [] -> runStdin check
            ["-"] -> runStdin check
            _
                | check -> runCheck files
                | otherwise -> runFormat files

-- | Options may appear anywhere; @-@ and non-flag words are file operands.
-- Any other @-@-prefixed word is an unknown option.
parseArgs :: [String] -> Either String Command
parseArgs = go False []
  where
    go check files (a : as) = case a of
        "--check" -> go True files as
        "-h" -> Right Help
        "--help" -> Right Help
        "--version" -> Right Version
        "-" -> go check (files ++ ["-"]) as
        ('-' : _) -> Left ("hledger-fmt: unknown option: " ++ a)
        _ -> go check (files ++ [a]) as
    go check files [] = Right (Run check files)

runStdin :: Bool -> IO ()
runStdin check = do
    src <- getContents
    if check
        then unless (isFormatted src) exitFailure
        else putStr (format src)

-- | Format each file in place. A file that cannot be read or written is
-- reported on stderr and skipped; the run then exits non-zero.
runFormat :: [FilePath] -> IO ()
runFormat files = do
    oks <- forM files $ \path ->
        onFile path $ \src -> do
            let out = format src
            when (out /= src) $ writeFileUtf8 path out
            pure True
    unless (and oks) exitFailure

-- | Write nothing; exit non-zero if any file is not already formatted (listing
-- offenders on stderr) or cannot be read.
runCheck :: [FilePath] -> IO ()
runCheck files = do
    oks <- forM files $ \path ->
        onFile path $ \src ->
            if isFormatted src
                then pure True
                else hPutStrLn stderr ("unformatted: " ++ path) >> pure False
    unless (and oks) exitFailure

-- | Read a file and run an action on its contents, turning any IO error into a
-- stderr message and a 'False' result instead of an uncaught exception. The
-- action's own 'Bool' (e.g. \"already formatted\") is passed through on success.
onFile :: FilePath -> (String -> IO Bool) -> IO Bool
onFile path act = do
    r <- try (readFileUtf8 path >>= act)
    case r of
        Right ok -> pure ok
        Left e -> do
            hPutStrLn stderr ("hledger-fmt: " ++ show (e :: IOException))
            pure False

readFileUtf8 :: FilePath -> IO String
readFileUtf8 path = openFileUtf8 path ReadMode >>= hGetContents'

writeFileUtf8 :: FilePath -> String -> IO ()
writeFileUtf8 path s = do
    h <- openFileUtf8 path WriteMode
    hPutStr h s
    hClose h

openFileUtf8 :: FilePath -> IOMode -> IO Handle
openFileUtf8 path mode = do
    h <- openFile path mode
    hSetEncoding h utf8
    pure h
