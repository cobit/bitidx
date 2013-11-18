module Import
    ( module Import
    , Json
    ) where

import           Prelude              as Import hiding (head, init, last,
                                                 readFile, tail, writeFile)
import           Yesod                as Import hiding (Route (..))
import           Yesod.Auth

import           Control.Applicative  as Import (pure, (<$>), (<*>))
import           Control.Monad        as Import
import           Data.Maybe           as Import
import           Data.Default         as Import
import           Data.Text            as Import (Text)
import           Data.List as L
import           Foundation           as Import
import           Model                as Import
import           Settings             as Import
import           Settings.Development as Import
import           Settings.StaticFiles as Import

import Data.Torrent.InfoHash as Import

#if __GLASGOW_HASKELL__ >= 704
import           Data.Monoid          as Import
                                                 (Monoid (mappend, mempty, mconcat),
                                                 (<>))
#else
import           Data.Monoid          as Import
                                                 (Monoid (mappend, mempty, mconcat))

infixr 5 <>
(<>) :: Monoid m => m -> m -> m
(<>) = mappend
#endif

type Json = Value
