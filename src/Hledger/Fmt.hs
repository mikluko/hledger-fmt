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
    formatSorted,
    isFormatted,
    isFormattedSorted,
) where

import Data.Char (isDigit, isSpace)
import Data.List (sortBy)
import Data.Ord (comparing)

-- | Format a whole file's contents. Output always ends in a newline (empty
-- input yields empty output). Idempotent: @format (format x) == format x@.
format :: String -> String
format = unlines . formatLines . lines

-- | Like 'format', but also stably sorts transactions by date. Sorting is
-- directive-bounded: transactions reorder only within runs between directives
-- and standalone comment blocks, which act as barriers, so positional
-- directives (@Y@, @apply account@, @alias@) keep their scope. Transactions
-- with the same date keep their source order.
formatSorted :: String -> String
formatSorted = unlines . formatLines . sortEntries . lines

-- | Whether the input is already in formatted form (a fixed point of
-- 'format'). Used by @--check@.
isFormatted :: String -> Bool
isFormatted s = format s == s

-- | Whether the input is already sorted and formatted (a fixed point of
-- 'formatSorted'). Used by @--check --sort@.
isFormattedSorted :: String -> Bool
isFormattedSorted s = formatSorted s == s

-- ---------------------------------------------------------------------------
-- Sorting
-- ---------------------------------------------------------------------------

-- | One chunk of the file for sorting purposes.
data Entry
    = -- | A single blank line (a separator; kept in place).
      EBlank
    | -- | A directive or standalone comment block: a barrier that transactions
      -- are never reordered across.
      EAnchor [String]
    | -- | A transaction: its date key and its lines (any leading comment lines
      -- attached above the header, the header, and its posting lines).
      ETxn (Int, Int, Int) [String]

-- | Stably sort transactions by date within each directive-bounded run, then
-- flatten back to lines.
sortEntries :: [String] -> [String]
sortEntries = concatMap entryLines . sortRuns . parseEntries

entryLines :: Entry -> [String]
entryLines EBlank = [""]
entryLines (EAnchor ls) = ls
entryLines (ETxn _ ls) = ls

-- | Split the file into entries, attaching leading comment lines to the
-- transaction they head (a comment followed by a blank is standalone).
parseEntries :: [String] -> [Entry]
parseEntries = go []
  where
    -- pend: buffered leading comment lines awaiting the transaction they head.
    go pend (l : ls)
        | isBlank l = flush pend (EBlank : go [] ls)
        | isComment l = go (pend ++ [l]) ls
        | opensTxn l =
            let (post, rest) = span isIndentedNonBlank ls
             in ETxn (dateKey l) (pend ++ l : post) : go [] rest
        | otherwise =
            let (sub, rest) = span isIndentedNonBlank ls
             in EAnchor (pend ++ l : sub) : go [] rest
    go pend [] = flush pend []

    flush [] cont = cont
    flush pend cont = EAnchor pend : cont

-- | A line-start comment (not indented): @;@, @#@, or @*@.
isComment :: String -> Bool
isComment (c : _) = c == ';' || c == '#' || c == '*'
isComment _ = False

-- | Reorder transactions within each maximal run bounded by anchors.
sortRuns :: [Entry] -> [Entry]
sortRuns (EAnchor a : rest) = EAnchor a : sortRuns rest
sortRuns [] = []
sortRuns es =
    let (run, rest) = break isAnchor es
     in sortRun run ++ sortRuns rest
  where
    isAnchor (EAnchor _) = True
    isAnchor _ = False

-- | Stably sort the transactions in a run by date, leaving blank separators in
-- their original positions.
sortRun :: [Entry] -> [Entry]
sortRun run = refill run sorted
  where
    sorted = sortBy (comparing txnKey) [t | t@(ETxn _ _) <- run]
    txnKey (ETxn k _) = k
    txnKey _ = (0, 0, 0)
    refill (ETxn _ _ : rest) (s : ss) = s : refill rest ss
    refill (e : rest) ss = e : refill rest ss
    refill [] _ = []

-- | The sort key from a transaction header: its primary date parsed to
-- @(year, month, day)@. Unparseable dates sort first; the stable sort then
-- preserves their source order.
dateKey :: String -> (Int, Int, Int)
dateKey line =
    case map readInt (splitOn dateSeps primary) of
        [y, m, d] -> (y, m, d)
        [m, d] -> (0, m, d)
        _ -> (0, 0, 0)
  where
    token = takeWhile (not . isSpace) line
    primary = takeWhile (/= '=') token -- drop any =secondary-date
    dateSeps c = c == '/' || c == '-' || c == '.'

readInt :: String -> Int
readInt s = case reads s of
    [(n, "")] -> n
    _ -> 0

splitOn :: (Char -> Bool) -> String -> [String]
splitOn p s = case break p s of
    (chunk, []) -> [chunk]
    (chunk, _ : rest) -> chunk : splitOn p rest

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
        ++ amountField
        ++ (if null rest then "" else " " ++ unwords rest)
        ++ commentPart mc
  where
    amountField
        -- Amount-less posting carrying only a cost/assertion tail (@ /
        -- = ...): reserve the number and commodity columns with blanks so the
        -- tail lines up as if a zero amount stood in front of it.
        | null num = replicate numW ' ' ++ phantomCommodityPad rest
        | otherwise = padL num numW ++ (if null com then "" else " " ++ com)

-- | Blank padding standing in for the commodity of an omitted amount, taken
-- from the commodity of the cost/assertion tail (empty if it has none).
phantomCommodityPad :: [String] -> String
phantomCommodityPad rest = case tailCommodity rest of
    "" -> ""
    c -> " " ++ replicate (length c) ' '

-- | The commodity of a cost/assertion tail: the first token that is neither an
-- operator (@, @@, =, ==) nor a number.
tailCommodity :: [String] -> String
tailCommodity (t : ts)
    | isRestStart t = tailCommodity ts
    | isNumberLike t = tailCommodity ts
    | otherwise = t
tailCommodity [] = ""

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
