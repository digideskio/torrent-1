{-# LANGUAGE DeriveGeneric, DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Parses MetaInfo into a convenient structure.
module Network.BitTorrent.MetaInfo (
  MetaInfo(..)
, InfoDictionary(..)
, FileInfo(..)
, parseMetaInfo
) where

import Control.Applicative
import Control.DeepSeq
import Crypto.Hash.SHA1
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.Maybe
import Data.Word
import GHC.Generics (Generic)
import Lens.Family2
import Network.BitTorrent.Bencoding
import Network.BitTorrent.Bencoding.Lenses

data FileInfo = FileInfo {
  length :: Word64
, name   :: ByteString
} deriving(Eq, Show, Generic, NFData)

-- | Holds the info dictionary as described in the specification.
data InfoDictionary = InfoDictionary {
                      pieceLength :: Word32
                    , pieces      :: ByteString
                    , private     :: Maybe Bool
                    , files       :: [FileInfo]
                    } deriving(Eq, Show, Generic, NFData)

-- | Holds MetaInfo data as described in the specification.
data MetaInfo = MetaInfo {
                  info :: InfoDictionary
                , infoHash :: ByteString
                , announce :: ByteString
                , creationDate :: Maybe Word32
                } deriving(Eq, Show, Generic, NFData)

-- | Parses a 'BValue' to extract the MetaInfo dictionary.
parseMetaInfo :: BValue -> Maybe MetaInfo
parseMetaInfo bv = MetaInfo
                     <$> ((bv ^? bkey "info") >>= parseInfoDictionary)
                     <*> (hash . serialize <$> (bv ^? bkey "info"))
                     <*> bv ^? (bkey "announce" . bstring)
                     <*> pure (fromIntegral <$> bv ^? (bkey "creation date" . bnumber))

parseInfoDictionary :: BValue -> Maybe InfoDictionary
parseInfoDictionary bv = InfoDictionary
                           <$> (fromIntegral <$> bv ^? (bkey "piece length" . bnumber))
                           <*> bv ^? (bkey "pieces" . bstring)
                           <*> pure ((==1) <$> bv ^? (bkey "private" . bnumber))
                           <*> parseFiles bv

parseFiles :: BValue -> Maybe [FileInfo]
parseFiles bv = (pure <$> parseSingleFile bv) <|> parseMultipleFiles
  where parseMultipleFiles :: Maybe [FileInfo]
        parseMultipleFiles = if all isJust allParsed
          then Just (fromJust <$> allParsed)
          else Nothing
        allParsed = parseSingleFile <$> bv ^.. (bkey "files" . blist)

parseSingleFile :: BValue -> Maybe FileInfo
parseSingleFile bv = FileInfo
                  <$> (fromIntegral <$> bv ^? (bkey "length" . bnumber))
                  <*> (bv ^? (bkey "name" . bstring)
                   <|> parsePath bv)


parsePath :: BValue -> Maybe ByteString
parsePath bv = if Prelude.null components then Nothing else Just (B.intercalate "-KEK-" components)
  where components = bv ^.. (bkey "path" . blist . bstring)
