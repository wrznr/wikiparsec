> {-# LANGUAGE OverloadedStrings #-}
> 
> module Text.MediaWiki.Sections where
> import Data.Text as T
> import Data.Text (Text)
> import Text.Parsec.Prim
> import Text.Parsec.Combinator
> import Control.Applicative

Data structures
===============

First we'll break the text into lines. Then we group these lines into
individual sections with their headings. Finally, we step through the
sections, converting them into contextualized WikiSection objects that know
about their entire stack of headings.

Here we define the data structures representing the outputs of these various
steps.

> data SingleSection = SingleSection {
>   ssLevel :: Int,
>   ssHeading :: Text,
>   ssContent :: Text
> } deriving (Eq, Show)

> data WikiSection = WikiSection {
>   headings :: [Text],
>   content :: Text
> } deriving (Eq, Show)
>
> data TextLine = Heading Int Text | Plain Text deriving (Eq, Show)
>
> isHeading :: TextLine -> Bool
> isHeading (Heading _ _) = True
> isHeading _             = False


Reading lines
=============

This is a kind of lexer for the section parser. We sort the lines of the page
into two types: headings and non-headings.

> readLines :: Text -> [TextLine]
> readLines text = map parseTextLine (lines text)
>
> parseTextLine :: Text -> TextLine
> parseTextLine text =
>   let (innerText, level) = headingWithLevel (T.strip text)
>   in  (if level == 0 then (Plain innerText) else (Heading level innerText))
>
> headingWithLevel :: Text -> (Text, Int)
> headingWithLevel text =
>   if (length text) > 1 && T.isPrefixOf "=" text && T.isSuffixOf "=" text
>     then let (innerText, innerLevel) = headingWithLevel text
>          in  (innerText, innerLevel + 1)
>     else (text, 0)


A line-by-line parser
=====================

> type LineParser = Parsec [TextLine] ()

Here's some boilerplate to help Parsec understand that our tokens are lines:

> matchLine :: LineParser 
> matchLine pred =
>   let showLine = show
>       testLine line = if pred line then Just line else Nothing
>       nextPos pos x xs = updatePosLine pos x
>   in  tokenPrim showLine nextPos testLine
>
> updatePosLine (SourcePos name line column) _ = SourcePos name (line+1) 1

Now we can use it to define two token-matching parsers:

> pPlainLine :: Parser TextLine
> pPlainLine = matchLine (not isHeading)
>
> pHeadingLine :: Parser TextLine
> pHeadingLine = matchLine isHeading


Parsing sections
================

> pSection :: Parser SingleSection
> pSection = do
>   Heading level name <- pHeadingLine
>   textLines <- many pPlainLine
>   return (SingleSection { ssLevel = level, ssHeading = name, ssContent = unlines textLines })


Converting sections
===================

Here's how we convert a list of SingleSections into a list of contextualized
WikiSections.

> convertSections :: [SingleSection] -> [WikiSection]
> convertSections = processSectionHeadings ["top"]
>
> processSectionHeadings :: [Text] -> [SingleSection] -> [WikiSection]
> processSectionHeadings headingStack [] = []
> processSectionHeadings headingStack (sec:rest) =
>   let sec' = (applyHeadings headingStack sec)
>       heds = (headings section)
>   in  (sec':(processSectionHeadings heds rest))
>
> applyHeadings :: [Text] -> SingleSection -> WikiSection
> applyHeadings headingStack sec =
>   let heds = (take ((ssLevel sec) - 1) headingStack) ++ [ssHeading sec]
>   in  WikiSection { headings = heds, content = ssContent sec }


Parsing the whole page
======================

It's convenient for us if all text is in a section. The text that precedes any
section headings is effectively in a level-1 section called "top". Let's just
add the heading for it.

> preparePage :: Text -> Text
> preparePage text = "=top=\n" ++ text
>
> pPage :: Parser [WikiSection]
> pPage = convertSections <$> many pSection
>
> parsePageIntoSections :: Text -> Either ParseError [WikiSection]
> parsePageIntoSections text = parse pPage "" (preparePage text)