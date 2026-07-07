-- | Format-preserving hledger journal formatter.
--
-- Line-oriented: never builds a semantic model. Each physical line is
-- classified and only posting lines are reflowed; everything else passes
-- through (directives and comments verbatim, transaction headers with
-- trailing whitespace trimmed). Because directives pass through untouched,
-- price-only and include-only files are safe by construction.
--
-- Amounts are aligned to a single file-wide column: the account field is
-- padded past the longest account name in the file, and every first-amount
-- number is right-aligned to one shared column across all transactions.
module Hledger.Fmt (
    format,
    isFormatted,
) where

import Data.Char (isDigit, isSpace)

-- | Format a whole file's contents. Output always ends in a newline (empty
-- input yields empty output). Idempotent: @format (format x) == format x@.
format :: String -> String
format = unlines . formatLines . lines

-- | Whether the input is already in formatted form (a fixed point of
-- 'format'). Used by @--check@.
isFormatted :: String -> Bool
isFormatted s = format s == s

-- ---------------------------------------------------------------------------
-- Line dispatch
-- ---------------------------------------------------------------------------

-- | Reflow a list of physical lines. Alignment widths are computed once over
-- every posting in the file (first pass), then each posting run is rendered
-- against those shared widths. An indented, non-blank run counts as postings
-- only when it follows a transaction header; otherwise it passes through
-- verbatim, so indented sub-directives under @account@/@commodity@ are left
-- untouched. Every non-posting line is emitted by 'formatOther'.
formatLines :: [String] -> [String]
formatLines ls = go False ls
  where
    posts = map parsePosting (concat (postingRuns ls))
    accW = maximum0 [length a | Just a <- map accountOf posts]
    numW = maximum0 [length n | PAmount _ n _ _ _ <- posts]

    go inTxn (l : rest)
        | inTxn && isIndentedNonBlank l =
            let (grp, more) = span isIndentedNonBlank (l : rest)
             in map (render accW numW . parsePosting) grp ++ go True more
        | otherwise = formatOther l : go (opensTxn l) rest
    go _ [] = []

-- | The maximal runs of posting lines in the file: indented, non-blank lines
-- that follow a transaction header.
postingRuns :: [String] -> [[String]]
postingRuns = go False
  where
    go inTxn (l : rest)
        | inTxn && isIndentedNonBlank l =
            let (grp, more) = span isIndentedNonBlank (l : rest)
             in grp : go True more
        | otherwise = go (opensTxn l) rest
    go _ [] = []

-- | The account name of a posting that has one (comment lines have none).
accountOf :: Posting -> Maybe String
accountOf (PAmount a _ _ _ _) = Just a
accountOf (PBare a _) = Just a
accountOf (PComment _) = Nothing

-- | Whether a line opens a transaction, so a following indented run is
-- postings. A blank line or a directive ends the transaction.
opensTxn :: String -> Bool
opensTxn (c : _) = isDigit c
opensTxn _ = False

-- | An indented, non-blank line: a posting (or an in-transaction comment).
isIndentedNonBlank :: String -> Bool
isIndentedNonBlank s@(c : _) = isSpace c && not (isBlank s)
isIndentedNonBlank _ = False

isBlank :: String -> Bool
isBlank = all isSpace

-- | Non-posting lines. Blank lines collapse to empty (grouping preserved);
-- transaction headers (column 0, starting with a digit) get trailing
-- whitespace trimmed; everything else (directives, top-level comments,
-- includes, price directives) passes through verbatim.
formatOther :: String -> String
formatOther s
    | isBlank s = ""
    | opensTxn s = rstrip s
    | otherwise = s

-- ---------------------------------------------------------------------------
-- Posting group
-- ---------------------------------------------------------------------------

-- | A parsed posting line.
data Posting
    = -- | Standalone in-transaction comment line (indented @;@ ...).
      PComment String
    | -- | Amount-less posting: account plus optional inline comment.
      PBare String (Maybe String)
    | -- | account, number field, commodity, cost/assertion tokens, comment.
      PAmount String String String [String] (Maybe String)

maximum0 :: [Int] -> Int
maximum0 [] = 0
maximum0 xs = maximum xs

render :: Int -> Int -> Posting -> String
render _ _ (PComment c) = indent ++ c
render _ _ (PBare acc mc) = indent ++ acc ++ commentPart mc
render accW numW (PAmount acc num com rest mc) =
    indent
        ++ padR acc accW
        ++ "  "
        ++ padL num numW
        ++ (if null com then "" else " " ++ com)
        ++ (if null rest then "" else " " ++ unwords rest)
        ++ commentPart mc

indent :: String
indent = "    "

commentPart :: Maybe String -> String
commentPart Nothing = ""
commentPart (Just c) = "  " ++ c

padR :: String -> Int -> String
padR s n = s ++ replicate (n - length s) ' '

padL :: String -> Int -> String
padL s n = replicate (n - length s) ' ' ++ s

-- | Parse one posting line (leading indent and trailing whitespace ignored).
parsePosting :: String -> Posting
parsePosting raw =
    let s = rstrip (dropWhile isSpace raw)
     in if take 1 s == ";"
            then PComment s
            else
                let (body, mc) = splitComment s
                 in case splitAccountAmount body of
                        (acc, "") -> PBare acc mc
                        (acc, amt) ->
                            let (num, com, rest) = splitAmount (words amt)
                             in PAmount acc num com rest mc

-- | Split off a trailing inline comment beginning at the first @;@. Accounts
-- and amounts never contain @;@, so the first one is the boundary.
splitComment :: String -> (String, Maybe String)
splitComment s = case break (== ';') s of
    (before, "") -> (rstrip before, Nothing)
    (before, cmt) -> (rstrip before, Just cmt)

-- | Split a posting body into account and amount on the first account/amount
-- separator. hledger's separator is a run of two or more whitespace
-- characters (spaces and\/or tabs); a single space or a single tab is not a
-- separator, so account names may contain single spaces. No separator means
-- the whole body is the account (an amount-less posting).
splitAccountAmount :: String -> (String, String)
splitAccountAmount = go ""
  where
    go acc rest@(c : cs)
        | isSeparator rest = (reverse acc, dropWhile isSep rest)
        | otherwise = go (c : acc) cs
    go acc [] = (reverse acc, "")

-- | Whether the given position begins an account/amount separator: two or
-- more consecutive whitespace characters.
isSeparator :: String -> Bool
isSeparator (c1 : c2 : _) = isSep c1 && isSep c2
isSeparator _ = False

isSep :: Char -> Bool
isSep c = c == ' ' || c == '\t'

-- | Split amount tokens into (number field, commodity, remaining tokens).
-- Remaining tokens are the cost (@ \/ @@) and balance assertion (= \/ ==),
-- kept verbatim and never column-aligned.
splitAmount :: [String] -> (String, String, [String])
splitAmount toks =
    let (amt, rest) = break isRestStart toks
     in case amt of
            [] -> ("", "", rest)
            [t] -> (t, "", rest)
            (t0 : t1 : more)
                | isNumberLike t0 -> (t0, t1, more ++ rest)
                | isNumberLike t1 && null more -> (unwords [t0, t1], "", rest)
                | otherwise -> (unwords amt, "", rest)

-- | A token that begins the cost or assertion tail.
isRestStart :: String -> Bool
isRestStart t = take 1 t == "@" || take 1 t == "="

-- | Whether a token reads as a bare number (right-alignable). Rejects
-- commodity-on-left tokens like @$100@ and bare commodities like @AMD@.
isNumberLike :: String -> Bool
isNumberLike [] = False
isNumberLike s@(c : _) = c `elem` "+-.0123456789" && any isDigit s

rstrip :: String -> String
rstrip = reverse . dropWhile isSpace . reverse
