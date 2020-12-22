{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DeriveLift #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

module Aws.Lambda.Runtime.Common
  ( RunCallback,
    LambdaResult (..),
    LambdaError (..),
    LambdaOptions (..),
    DispatcherOptions (..),
    ApiGatewayDispatcherOptions (..),
    DispatcherStrategy (..),
    ToLambdaResponseBody (..),
    HandlerType (..),
    RawEventObject,
    unLambdaResponseBody,
    defaultDispatcherOptions,
  )
where

import Aws.Lambda.Runtime.ApiGatewayInfo
import Aws.Lambda.Runtime.Context (Context)
import Aws.Lambda.Utilities
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.ByteString.Lazy as Lazy
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Generics (Generic)
import Language.Haskell.TH.Syntax (Lift)

-- | API Gateway specific dispatcher options
newtype ApiGatewayDispatcherOptions = ApiGatewayDispatcherOptions
  { -- | Should impure exceptions be propagated through the API Gateway interface
    propagateImpureExceptions :: Bool
  }
  deriving (Lift)

-- | Options that the dispatcher generator expects
newtype DispatcherOptions = DispatcherOptions
  { apiGatewayDispatcherOptions :: ApiGatewayDispatcherOptions
  }
  deriving (Lift)

defaultDispatcherOptions :: DispatcherOptions
defaultDispatcherOptions =
  DispatcherOptions (ApiGatewayDispatcherOptions True)

-- | A strategy on how to generate the dispatcher functions
data DispatcherStrategy
  = UseWithAPIGateway
  | StandaloneLambda
  deriving (Lift)

-- | Callback that we pass to the dispatcher function
type RunCallback (t :: HandlerType) context =
  LambdaOptions context -> IO (Either (LambdaError t) LambdaResult)

-- | Wrapper type for lambda response body
newtype LambdaResponseBody = LambdaResponseBody {unLambdaResponseBody :: Text}
  deriving newtype (ToJSON, FromJSON)

class ToLambdaResponseBody a where
  toStandaloneLambdaResponse :: a -> LambdaResponseBody

-- We need to special case String and Text to avoid unneeded encoding
-- which results in extra quotes put around plain text responses
instance {-# OVERLAPPING #-} ToLambdaResponseBody String where
  toStandaloneLambdaResponse = LambdaResponseBody . Text.pack

instance {-# OVERLAPPING #-} ToLambdaResponseBody Text where
  toStandaloneLambdaResponse = LambdaResponseBody

instance ToJSON a => ToLambdaResponseBody a where
  toStandaloneLambdaResponse = LambdaResponseBody . toJSONText

data HandlerType =
  StandaloneHandlerType |
  APIGatewayHandlerType

-- | Wrapper type for lambda execution results
data LambdaError (t :: HandlerType) where
  StandaloneLambdaError :: LambdaResponseBody -> LambdaError 'StandaloneHandlerType
  ApiGatewayLambdaError :: ApiGatewayResponse ApiGatewayResponseBody -> LambdaError 'APIGatewayHandlerType

-- | Wrapper type to handle the result of the user
data LambdaResult
  = StandaloneLambdaResult LambdaResponseBody
  | ApiGatewayResult (ApiGatewayResponse ApiGatewayResponseBody)

type RawEventObject = Lazy.ByteString

-- | Options that the generated main expects
data LambdaOptions context = LambdaOptions
  { eventObject :: !RawEventObject,
    functionHandler :: !Text,
    executionUuid :: !Text,
    contextObject :: !(Context context)
  }
  deriving (Generic)
