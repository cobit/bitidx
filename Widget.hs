-- suppress warnings caused by autogenerated names in Hamlet's
-- RecordWildCards
{-# OPTIONS -w #-}
module Widget
       ( CommentView
       , BlankForm

         -- * Utils
       , withFormResult

         -- * Errors
       , invalidTorrentFileW
       , torrentNotExistW
       , alreadyExistW

         -- * Main Pages
       , homePage
       , searchPage
       , addReleasePage
       , releasePage

         -- * Add release page
       , NewRelease (..)
       , addForm
       , addedSuccessfullyMessage

         -- * Release subpages
         -- ** Description
       , Description (..)
       , descriptionForm
       , descriptionPage

         -- ** Metadata
       , metadataForm
       , metadataEditorPage

         -- ** Discussion
       , commentForm
       , discussionPage

         -- * User
       , userProfilePage
       , userEditPage

         -- * Other pages
       , helpW
       ) where

import Prelude
import Control.Applicative
import Control.Monad
import Data.Bool
import Data.Functor
import Data.List as L
import Data.Maybe
import Data.Monoid
import Data.Text as T
import Data.Text.Encoding as T
import Data.Text.Lazy as TL
import Data.Text.Lazy.Builder as TL
import Data.Text.Lazy.Builder.Int as TL
import Data.Text.Lazy.Builder.RealFloat as TL
import Data.Time.Clock.POSIX -- TODO local time
import Network.Gravatar
import Network.URI
import Text.Markdown
import Text.Show
import Yesod as Y

import Foundation
import Model
import Model.Entities
import Settings

import Data.Torrent
import Data.Torrent.Layout
import Data.Torrent.InfoHash
import Data.Torrent.Magnet
import Data.Torrent.Piece
import Data.Torrent.Client

import Handler.User.Permissions


{-----------------------------------------------------------------------
--  Utils
-----------------------------------------------------------------------}

tinyUserpic :: GravatarOptions
tinyUserpic = def
  { gDefault = Just Identicon
  , gSize    = Just (Size 25)
  }

largeUserpic :: GravatarOptions
largeUserpic = def
  { gDefault = Just Identicon
  , gSize    = Just (Size 150)
  }

showSize :: Integral a => a -> TL.Text
showSize = toLazyText . truncate
  where
    truncate i
      | i >= gib
      , t <- fromIntegral i / fromIntegral gib :: Double
      = formatRealFloat Fixed (Just 3) t  <> "GiB"
      | i >= mib  = decimal (i `div` mib) <> "MiB"
      | i >= kib  = decimal (i `div` kib) <> "KiB"
      | otherwise = decimal i <> "B"

    (gib, mib, kib) = (1024 ^ 3, 1024 ^ 2, 1024 ^ 1)

type BlankForm = (Widget, Enctype)

formFailure reasons = do
  defaultLayout $ do
    setTitleI MsgFormFailurePageTitle
    [whamlet|
     $forall reason <- reasons
       #{show reason}
      |]

withFormResult  FormMissing          _      = notFound
withFormResult (FormFailure reasons) _      = formFailure reasons
withFormResult (FormSuccess result ) action = action result

{-----------------------------------------------------------------------
--  Errors
-----------------------------------------------------------------------}

torrentNotExistW :: Widget
torrentNotExistW = [whamlet|
    <p .error> This torrent do not exist or probably has been deleted by the author.
  |]

invalidTorrentFileW :: Widget
invalidTorrentFileW = do
  setTitleI MsgInvalidTorrentPageTitle
  $(widgetFile "error/invalid-file")

alreadyExistW :: InfoHash -> Widget
alreadyExistW ih = do
  setTitleI MsgAlreadyExistPageTitle
  $(widgetFile "error/already-exist")

{-----------------------------------------------------------------------
--  Add release page
-----------------------------------------------------------------------}

data NewRelease = NewRelease
  { torrentName :: T.Text
  , torrentFile :: Y.FileInfo
  }

addForm :: Form NewRelease
addForm = renderDivs $ do
  NewRelease
    <$> areq textField "Name" Nothing
    <*> fileAFormReq   "Choose a .torrent file"

addReleasePage :: BlankForm -> Widget
addReleasePage (formWidget, formEnctype) = do
  setTitleI MsgAddReleasePageTitle
  $(widgetFile "add/upload")

addedSuccessfullyMessage :: Html
addedSuccessfullyMessage = [shamlet|
    <div .label-success> Torrent successufully added to database.
  |]

{-----------------------------------------------------------------------
--  Description editor
-----------------------------------------------------------------------}

nameInput :: FieldSettings App
nameInput =  FieldSettings
  { fsLabel   = SomeMessage MsgNameLabel
  , fsTooltip = Nothing
  , fsId      = Just "name"
  , fsName    = Just "name"
  , fsAttrs   = [ ("placeholder", "Enter release name...")
                , ("accesskey"  , "N")
                ]
  }

descriptionInput :: FieldSettings App
descriptionInput =  FieldSettings
  { fsLabel   = SomeMessage MsgDescriptionLabel
  , fsTooltip = Nothing
  , fsId      = Just "description"
  , fsName    = Just "description"
  , fsAttrs   = [ ("placeholder", "Enter release description...")
                , ("accesskey"  , "D")
                ]
  }

data Description = Description
  { name        :: T.Text
  , description :: Maybe Textarea
  }

descriptionForm :: Description -> Form Description
descriptionForm Description {..} = renderBootstrap $ do Description
  <$> areq textField     nameInput        (Just name)
  <*> aopt textareaField descriptionInput (Just description)

descriptionW :: BlankForm -> InfoHash -> Widget
descriptionW (widget, enctype) ih = $(widgetFile "torrent/description")

descriptionPage :: BlankForm -> InfoHash -> T.Text -> Widget
descriptionPage form ih name = do
  setTitleI (MsgEditDescriptionPageTitle name)
  descriptionW form ih

{-----------------------------------------------------------------------
--  Metadata editor
-----------------------------------------------------------------------}
-- TODO more fields
-- TODO detalize fields
-- TODO use yesod forms for search form

uriToText :: URI -> T.Text
uriToText = T.pack . show

textToURI :: T.Text -> Maybe URI
textToURI = parseURI . T.unpack

uriField :: Field Handler URI
uriField =  Field
  { fieldParse = \ ts fs -> do
       emuri <- fieldParse urlField ts fs
       return $ (textToURI =<<) <$> emuri
  , fieldView = \theId name attrs val ->
       fieldView parent theId name attrs (uriToText <$> val)
  , fieldEnctype = fieldEnctype parent
  }
  where
    parent = urlField :: Field Handler T.Text

textareaTextField :: Field Handler T.Text
textareaTextField = Field
  { fieldParse   = \ ts fs -> do
       emTextarea <- fieldParse textareaField ts fs
       return $ fmap unTextarea <$> emTextarea
  , fieldView = \theId name attrs val ->
       fieldView parent theId name attrs (Textarea <$> val)
  , fieldEnctype = fieldEnctype parent
  }
  where
    parent = textareaField :: Field Handler Textarea

-- TODO validate if announce url is valid (by spec)
announceInput :: FieldSettings App
announceInput =  FieldSettings
  { fsLabel   = SomeMessage MsgAnnounceLabel
  , fsTooltip = Just $ SomeMessage MsgAnnounceTooltip
  , fsId      = Just "announce"
  , fsName    = Just "announce"
  , fsAttrs   = [ ("placeholder", "Tracker URL...")
                , ("accesskey"  , "a")
                ]
  }

announceListInput :: FieldSettings App
announceListInput =  FieldSettings
  { fsLabel   = SomeMessage MsgAnnounceListLabel
  , fsTooltip = Just $ SomeMessage MsgAnnounceListTooltip
  , fsId      = Just "announceList"
  , fsName    = Just "announceList"
  , fsAttrs   = [ ("placeholder", "Tracker tiers...") ]
  }

announceListField :: Field Handler [[URI]]
announceListField = undefined -- uriField

commentInput :: FieldSettings App
commentInput  = FieldSettings
  { fsLabel   = SomeMessage MsgCommentLabel
  , fsTooltip = Just $ SomeMessage MsgCommentTooltip
  , fsId      = Just "comment"
  , fsName    = Just "comment"
  , fsAttrs   = [("placeholder", "Freeform author comment...")]
  }

createdByInput :: FieldSettings App
createdByInput  = FieldSettings
  { fsLabel   = SomeMessage MsgCreatedByLabel
  , fsTooltip = Just $ SomeMessage MsgCreatedByTooltip
  , fsId      = Just "createdBy"
  , fsName    = Just "createdBy"
  , fsAttrs   = [("placeholder", "Software name...")]
  }

createdByField :: Field Handler T.Text
createdByField = selectFieldList $ L.map (\ x -> (x, x)) names
  where
    names = L.map (T.pack . L.tail . show) ([succ minBound..maxBound] :: [ClientImpl])

creationDateInput :: FieldSettings App
creationDateInput =  FieldSettings
  { fsLabel   = SomeMessage MsgCreationDateLabel
  , fsTooltip = Just $ SomeMessage MsgCreationDateTooltip
  , fsId      = Just "creationDate"
  , fsName    = Just "creationDate"
  , fsAttrs   = []
  }

encodingInput :: FieldSettings App
encodingInput  = FieldSettings
  { fsLabel   = SomeMessage MsgEncodingLabel
  , fsTooltip = Just $ SomeMessage MsgEncodingTooltip
  , fsId      = Just "encoding"
  , fsName    = Just "encoding"
  , fsAttrs   = [("placeholder", "Character set...")]
  }

encodingField :: Field Handler T.Text
encodingField = textField

publisherURLInput :: FieldSettings App
publisherURLInput =  FieldSettings
  { fsLabel   = SomeMessage MsgPublisherURLLabel
  , fsTooltip = Just $ SomeMessage MsgPublisherURLTooltip
  , fsId      = Just "publisherURL"
  , fsName    = Just "publisherURL"
  , fsAttrs   = [("placeholder", "TODO")]
  }

metadataForm :: Torrent -> Form Torrent
metadataForm Torrent {..} = renderBootstrap $ do Torrent
  <$> areq uriField          announceInput     (Just tAnnounce)
  <*> pure tAnnounceList     -- TODO
--  <*> aopt announceListField announceListInput (Just tAnnounceList)
  <*> aopt textareaTextField commentInput      (Just tComment)
  <*> aopt createdByField    createdByInput    (Just tCreatedBy)
  <*> pure tCreationDate     -- TODO
  <*> aopt encodingField     encodingInput     (Just tEncoding)
  <*> pure tInfoDict
  <*> pure tPublisher        -- TODO
  <*> aopt uriField          publisherURLInput (Just tPublisherURL)
  <*> pure tSignature

metadataEditorW :: BlankForm -> InfoHash -> Widget
metadataEditorW (widget, enctype) ih = $(widgetFile "torrent/metadata-edit")

metadataEditorPage :: BlankForm -> InfoHash -> Widget
metadataEditorPage form ih = do
  setTitleI MsgEditMetadataPageTitle
  metadataEditorW form ih

metadataW :: Torrent -> Widget
metadataW torrent = $(widgetFile "torrent/metadata")

{-----------------------------------------------------------------------
--  Discussion page
-----------------------------------------------------------------------}

userCommentInput :: FieldSettings App
userCommentInput =  FieldSettings
  { fsLabel   = ""
  , fsTooltip = Nothing
  , fsId      = Just "comment"
  , fsName    = Just "comment"
  , fsAttrs   = [("placeholder", "Leave a message...")]
  }

type CommentView = (Entity Comment, Entity User)

commentForm :: Form Textarea
commentForm = renderBootstrap $ do
  areq textareaField userCommentInput Nothing

discussionW :: BlankForm -> Release -> [CommentView] -> Permissions -> Widget
discussionW (formWidget, formEnctype) Release {..} comments Permissions {..} = do
  $(widgetFile "torrent/discussion")

discussionPage :: BlankForm -> Release -> [CommentView] -> Permissions -> Widget
discussionPage form release @ Release {..} comments permissions = do
  setTitleI (MsgDiscussionPageTitle releaseName)
  discussionW form release comments permissions

{-----------------------------------------------------------------------
--  Main pages
-----------------------------------------------------------------------}

homePage :: [Release] -> Widget
homePage releases = do
  aDomId <- newIdent
  setTitleI MsgAppName
  $(widgetFile "homepage")
  releaseListW releases

helpW :: Widget
helpW = do
  setTitleI MsgHelpPageTitle
  $(widgetFile "help")

{-----------------------------------------------------------------------
--  Search page
-----------------------------------------------------------------------}

searchW :: Maybe T.Text -> Widget
searchW msearchString = $(widgetFile "search")


msgSearchPageTitle = maybe MsgSearchNoQueryPageTitle MsgSearchResultsPageTitle

searchPage :: Maybe T.Text -> [Release] -> Widget
searchPage msearchString releases = do
  setTitleI (msgSearchPageTitle msearchString)
  searchW msearchString
  when (isJust msearchString) $ do
    releaseListW releases

{-----------------------------------------------------------------------
--  Release page
-----------------------------------------------------------------------}

releaseListW :: [Release] -> Widget
releaseListW releases = $(widgetFile "torrent/list")

releaseW :: Release -> Permissions -> Widget
releaseW Release {..} Permissions {..} = $(widgetFile "torrent/release")

recentlyViewedW :: [InfoHash] -> Widget
recentlyViewedW infohashes = $(widgetFile "recently-viewed")

releasePage :: BlankForm -> Release -> [CommentView]
            -> Permissions -> [InfoHash] -> Widget
releasePage form release @ Release {..} comments permissions recent = do
  setTitleI (MsgReleasePageTitle releaseName)
  releaseW release permissions
  discussionW form release comments permissions
  recentlyViewedW recent

{-----------------------------------------------------------------------
--  User pages
-----------------------------------------------------------------------}

userProfilePage :: User -> Widget
userProfilePage User {..} = do
  setTitleI (MsgUserProfilePageTitle userScreenName)
  $(widgetFile "user/profile")

userEditPage :: BlankForm -> User -> Widget
userEditPage (formWidget, formEnctype) User {..} = do
  setTitleI (MsgUserEditPageTitle userScreenName)
  $(widgetFile "user/edit")

userMissingPage :: T.Text -> Widget
userMissingPage userName = do
  setTitleI MsgUserMissingPageTitle
  $(widgetFile "user/missing")
