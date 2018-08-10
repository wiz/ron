{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module RON.Binary.Serialize where

import           RON.Internal.Prelude

import qualified Data.Binary as Binary
import           Data.Bits (bit, shiftL, (.|.))
import           Data.ByteString.Lazy (cons, fromStrict)
import qualified Data.ByteString.Lazy as BSL
import           Data.Text (Text)
import           Data.Text.Encoding (encodeUtf8)
import           Data.ZigZag (zzEncode)

import           RON.Binary.Types (Desc (..), Size, descIsOp)
import           RON.Internal.Word (Word4, b0000, leastSignificant4, safeCast)
import           RON.Types (Atom (..), Chunk (..), Frame, Op (..),
                            ReducedChunk (..), UUID (..))

serialize :: Frame -> Either String ByteStringL
serialize frame = ("RON2" <>) <$> serializeBody
  where
    serializeBody = foldChunks =<< traverse serializeChunk frame

    chunkSize :: Bool -> Int64 -> Either String ByteStringL
    chunkSize continue x
        | x < bit 31 = Right $ Binary.encode s'
        | otherwise  = Left $ "chunk size is too big: " ++ show x
      where
        s = fromIntegral x :: Size
        s'  | continue  = s .|. bit 31
            | otherwise = s

    foldChunks :: [ByteStringL] -> Either String ByteStringL
    foldChunks = \case
        []   -> chunkSize False 0
        [c]  -> (<> c) <$> chunkSize False (BSL.length c)
        c:cs ->
            mconcat <$>
            sequence [chunkSize True (BSL.length c), pure c, foldChunks cs]

serializeChunk :: Chunk -> Either String ByteStringL
serializeChunk = \case
    Raw op         -> serializeOp DOpRaw op
    Reduced rchunk -> serializeReducedChunk rchunk

serializeOp :: Desc -> Op -> Either String ByteStringL
serializeOp desc Op{..} = do
    keys <- sequenceA
        [ serializeUuidType     opType
        , serializeUuidObject   opObject
        , serializeUuidEvent    opEvent
        , serializeUuidLocation opLocation
        ]
    payload <- traverse serializeAtom opPayload
    serializeWithDesc desc $ mconcat $ keys ++ payload
  where
    serializeUuidType     = serializeWithDesc DUuidType     . serializeUuid
    serializeUuidObject   = serializeWithDesc DUuidObject   . serializeUuid
    serializeUuidEvent    = serializeWithDesc DUuidEvent    . serializeUuid
    serializeUuidLocation = serializeWithDesc DUuidLocation . serializeUuid

serializeUuid :: UUID -> ByteStringL
serializeUuid (UUID x y) = Binary.encode x <> Binary.encode y

encodeDesc :: Desc -> Word4
encodeDesc = leastSignificant4 . fromEnum

serializeWithDesc
    :: Desc
    -> ByteStringL  -- ^ body
    -> Either String ByteStringL
serializeWithDesc d body = do
    (lengthDesc, lengthExtended) <- lengthFields
    let descByte = safeCast (encodeDesc d) `shiftL` 4 .|. safeCast lengthDesc
    pure $ descByte `cons` lengthExtended <> body
  where
    len = BSL.length body
    lengthFields
        | d == DAtomString = if
            | len == 0     -> Right (b0000, mkLengthExtended)
            | len < 16     -> Right (leastSignificant4 len, BSL.empty)
            | len < bit 31 -> Right (b0000, mkLengthExtended)
            | otherwise    -> Left "String is too long"
        | descIsOp d  = Right (b0000, BSL.empty)
        | len < 16    = Right (leastSignificant4 len, BSL.empty)
        | len == 16   = Right (b0000, BSL.empty)
        | otherwise   = error "impossible"
    mkLengthExtended
        | len < 128 = Binary.encode (fromIntegral len :: Word8)
        | otherwise = Binary.encode (fromIntegral len .|. bit 31 :: Word32)

serializeAtom :: Atom -> Either String ByteStringL
serializeAtom = \case
    AInteger i -> serializeWithDesc DAtomInteger $ Binary.encode $ zzEncode64 i
    AString  s -> serializeWithDesc DAtomString  $ serializeString s
    AUuid    u -> serializeWithDesc DAtomUuid    $ serializeUuid u
  where
    {-# INLINE zzEncode64 #-}
    zzEncode64 :: Int64 -> Word64
    zzEncode64 = zzEncode

serializeReducedChunk :: ReducedChunk -> Either String ByteStringL
serializeReducedChunk ReducedChunk{..} = do
    header <-
        serializeOp
            (if chunkIsQuery then DOpQueryHeader else DOpHeader)
            chunkHeader
    body <- mconcat <$> traverse (serializeOp DOpReduced) chunkBody
    pure $ header <> body

serializeString :: Text -> ByteStringL
serializeString = fromStrict . encodeUtf8
