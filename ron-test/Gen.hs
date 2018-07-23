{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumDecimals #-}

module Gen where

import           Data.Fixed (Fixed (MkFixed))
import           Data.Time (TimeOfDay (..), UTCTime (..), fromGregorian,
                            timeOfDayToTime)
import           Data.Word (Word64)
import           Hedgehog (MonadGen)
import           Hedgehog.Gen (bool, choice, enumBounded, integral, list, text,
                               unicode, word64)
import qualified Hedgehog.Range as Range

import           RON.Event (Event (..), ReplicaId (..))
import           RON.Internal.Word (Word60, leastSignificant60)
import           RON.Types (Atom (..), Chunk (..), Frame, Op (..),
                            ReducedChunk (..), UUID (..))

word64' :: MonadGen gen => gen Word64
word64' = word64 Range.linearBounded

word60 :: MonadGen gen => gen Word60
word60 = leastSignificant60 <$> word64'

uuid :: MonadGen gen => gen UUID
uuid = UUID <$> word64' <*> word64'

op :: MonadGen gen => Int -> gen Op
op size = Op <$> uuid <*> uuid <*> uuid <*> uuid <*> payload size

chunk :: MonadGen gen => Int -> gen Chunk
chunk size = choice [Raw <$> op size, Reduced <$> rchunk size]

rchunk :: MonadGen gen => Int -> gen ReducedChunk
rchunk size = ReducedChunk
    <$> op size
    <*> bool
    <*> list (Range.exponential 0 size) (op size)

frame :: MonadGen gen => Int -> gen Frame
frame size = list (Range.exponential 0 size) (chunk size)

frames :: MonadGen gen => Int -> gen [Frame]
frames size = list (Range.exponential 0 size) (frame size)

-- | Event time with year 2010—2350
eventTime :: MonadGen gen => gen UTCTime
eventTime = do
    y  <- integral $ Range.constant 2010 2350
    m  <- integral $ Range.constant 1 12
    d  <- integral $ Range.constant 1 31
    hh <- integral $ Range.constant 0 23
    mm <- integral $ Range.constant 0 59
    ss <- fmap (MkFixed . (*100000)) $ integral $ Range.constant 0 599999999
    pure UTCTime
        { utctDay     = fromGregorian y m d
        , utctDayTime = timeOfDayToTime $ TimeOfDay hh mm ss
        }

payload :: MonadGen gen => Int -> gen [Atom]
payload size = list (Range.exponential 0 size) (atom size)

atom :: MonadGen gen => Int -> gen Atom
atom size = choice
    [ AInteger  <$> integral (Range.exponentialFrom 0 (-10e10) 10e10)
    , AString   <$> text (Range.exponential 0 size) unicode
    , AUuid     <$> uuid
    ]

event :: MonadGen gen => gen Event
event = Event <$> eventTime <*> replicaId

replicaId :: MonadGen gen => gen ReplicaId
replicaId = ReplicaId <$> enumBounded <*> enumBounded <*> word60