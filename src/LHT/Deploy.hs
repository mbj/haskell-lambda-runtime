module LHT.Deploy
  ( buildTargetObject
  , byteStringTargetObject
  )
where

import Data.Text.Encoding (decodeUtf8)
import LHT.Executable
import LHT.Prelude

import qualified LHT.Build             as Build
import qualified LHT.S3                as S3
import qualified LHT.Zip               as Zip
import qualified Network.AWS           as AWS
import qualified Network.AWS.Data.Body as AWS
import qualified Network.AWS.S3.Types  as S3

buildTargetObject
  :: forall m . MonadUnliftIO m
  => Build.Config
  -> S3.BucketName
  -> m S3.TargetObject
buildTargetObject config bucketName =
  byteStringTargetObject bucketName <$> Build.build config

byteStringTargetObject
  :: S3.BucketName
  -> Executable
  -> S3.TargetObject
byteStringTargetObject bucketName (Executable bootstrap) =
  S3.TargetObject
    { message = "Uploading new lambda function: " <> objectKeyText
    , ..
    }
  where
    object        = AWS.toHashed $ Zip.mkZip bootstrap
    objectKeyText = decodeUtf8 (AWS.sha256Base16 object) <> ".zip"
    objectKey     = S3.ObjectKey objectKeyText