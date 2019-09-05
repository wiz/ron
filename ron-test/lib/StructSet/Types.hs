{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}

module StructSet.Types where

import           RON.Prelude

import           Data.Default (Default)
import           RON.Schema.TH (mkReplicated)

[mkReplicated|
    (struct_set StructSet13
        int1 Integer                 #ron{merge min}
        str2 RgaString
        str3 String                  #ron{merge LWW}
        set4 (ORSet StructSet13)
        set5 Integer                 #ron{merge set}
        nst6 StructSet13
        ref7 (ObjectRef StructSet13) #ron{merge set})
|]

deriving instance Default StructSet13
deriving instance Eq      StructSet13
deriving instance Generic StructSet13
deriving instance Show    StructSet13
