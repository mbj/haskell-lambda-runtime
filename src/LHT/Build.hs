module LHT.Build
  ( Config(..)
  , Executable(..)
  , Flag(..)
  , PackageName(..)
  , TargetName(..)
  , build
  )
where

import LHT.Executable
import LHT.Prelude
import System.Path ((</>))

import qualified CBT
import qualified CBT.Environment       as CBT
import qualified CBT.TH
import qualified Data.Foldable         as Foldable
import qualified System.Path           as Path
import qualified System.Path.Directory as Path
import qualified System.Posix.Files    as Files
import qualified UnliftIO.Exception    as Exception

newtype PackageName = PackageName Text
  deriving (Conversion Text) via Text

newtype TargetName = TargetName Text
  deriving (Conversion Text) via Text

data Flag = Flag PackageName Text

data Config = Config
  { executablePath :: Path.RelFile
  , flags          :: [Flag]
  , packageName    :: PackageName
  , targetName     :: TargetName
  }

prefix :: CBT.Prefix
prefix = CBT.Prefix "lht"

#ifndef __HLINT__
buildDefinition :: CBT.BuildDefinition
buildDefinition = $$(CBT.TH.readDockerfile (CBT.Prefix "lht") $ Path.file "Dockerfile")
  { CBT.verbosity = CBT.Verbose }
#endif

build :: CBT.HasEnvironment m => Config -> m Executable
build config@Config{..} =
  withBuildContainer config $ \containerName ->
    Executable <$> CBT.readContainerFile containerName (containerHomePath </> executablePath)

withBuildContainer :: CBT.HasEnvironment m => Config -> (CBT.ContainerName -> m a) -> m a
withBuildContainer Config{..} action = do
  containerName <- CBT.nextContainerName prefix

  hostProjectPath <- liftIO Path.getCurrentDirectory
  hostHomePath    <- liftIO Path.getHomeDirectory

  let
    containerProjectPath :: Path.AbsDir
    containerProjectPath = containerHomePath </> Path.relDir (convertText packageName)

    containerStackPath :: Path.AbsDir
    containerStackPath = containerHomePath </> Path.relDir ".stack"

    hostStackPath :: Path.AbsDir
    hostStackPath = hostHomePath </> Path.relDir ".stack-lht"

    hostStackWorkPath :: Path.AbsDir
    hostStackWorkPath = hostProjectPath </> Path.relDir ".stack-work-lht"

    containerDefinition = CBT.ContainerDefinition
      { detach           = CBT.Foreground
      , publishPorts     = []
      , remove           = CBT.NoRemove
      , removeOnRunFail  = CBT.Remove
      , imageName        = (CBT.imageName :: CBT.BuildDefinition -> CBT.ImageName) buildDefinition
      , workDir          = containerProjectPath
      , mounts =
        [ CBT.Mount { hostPath = hostProjectPath, containerPath = containerProjectPath }
        , CBT.Mount { hostPath = hostStackPath,   containerPath = containerStackPath }
        ]
      , programName      = "stack"
      , programArguments =
        [ "build"
        , "--allow-different-user"
        , "--copy-bins"
        , "--interleaved-output"
        , "--system-ghc"
        , "--work-dir", ".stack-work-lht"
        ] <> flagArguments <>
        [ convertText packageName <> ":" <> convertText targetName
        ]
      , ..
      }

  setupSharedDirectory hostStackPath
  setupSharedDirectory hostStackWorkPath

  Exception.bracket_
    (CBT.buildRun buildDefinition containerDefinition)
    (CBT.removeContainer containerName)
    (action containerName)

  where
    flagArguments :: [String]
    flagArguments = Foldable.foldMap mkFlag flags
      where
        mkFlag :: Flag -> [String]
        mkFlag (Flag name value) =
          ["--flag", convertText name <> ":" <> convertText value]

setupSharedDirectory :: MonadIO m => Path.AbsDir -> m ()
setupSharedDirectory path = liftIO $ do
  Path.createDirectoryIfMissing False path
  Files.setFileMode (Path.toString path) Files.accessModes

containerHomePath :: Path.AbsDir
containerHomePath = Path.absDir "/opt/build"
