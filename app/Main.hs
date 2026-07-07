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

import Control.Monad (forM, forM_, when)
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
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

main :: IO ()
main = do
    hSetBuffering stdout (BlockBuffering Nothing)
    mapM_ (`hSetEncoding` utf8) [stdin, stdout, stderr]
    args <- getArgs
    let (check, files) = parseArgs args
    case files of
        [] -> runStdin
        ["-"] -> runStdin
        _
            | check -> runCheck files
            | otherwise -> mapM_ formatInPlace files

-- | @--check@ anywhere flips check mode; everything else is a file operand.
parseArgs :: [String] -> (Bool, [String])
parseArgs = foldr step (False, [])
  where
    step "--check" (_, fs) = (True, fs)
    step f (c, fs) = (c, f : fs)

runStdin :: IO ()
runStdin = getContents >>= putStr . format

formatInPlace :: FilePath -> IO ()
formatInPlace path = do
    src <- readFileUtf8 path
    let out = format src
    when (out /= src) $ writeFileUtf8 path out

-- | Write nothing; exit non-zero if any file is not already formatted,
-- listing offenders on stderr.
runCheck :: [FilePath] -> IO ()
runCheck files = do
    offenders <- fmap concat . forM files $ \path -> do
        src <- readFileUtf8 path
        pure [path | not (isFormatted src)]
    if null offenders
        then exitSuccess
        else do
            forM_ offenders $ \p -> hPutStrLn stderr ("unformatted: " ++ p)
            exitFailure

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
