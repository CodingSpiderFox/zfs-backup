module Lib.List (list,listWith,localCmd,sshCmd) where
import Lib.Common(SSHSpec)
import Lib.ZFS (Object,objects,listShellCmd)
import Data.ByteString (ByteString)
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Attoparsec.Text as A
import qualified System.Process.Typed as P
import System.Exit (ExitCode(ExitSuccess,ExitFailure))
import Control.Concurrent.STM (STM, atomically)
import Data.Bifunctor (first)
import qualified Control.Exception as Ex

data ListError = CommandError ByteString | ZFSListParseError String deriving (Show, Ex.Exception)

list :: Maybe SSHSpec -> IO ()
list host = do
    res <- listWith $ case host of
        Nothing -> localCmd
        Just spec -> sshCmd spec
    either Ex.throw print res

listWith :: P.ProcessConfig () () () -> IO (Either ListError [Object])
listWith cmd = do
    output <- P.withProcessWait (allOutputs cmd) $ \proc -> do
        output <- fmap (TE.decodeUtf8 . LBS.toStrict) $ atomically $ P.getStdout proc
        err <- fmap LBS.toStrict $ atomically $ P.getStderr proc
        P.waitExitCode proc >>= \case
            ExitSuccess -> return (Right output)
            ExitFailure _i -> return $ Left $ CommandError err
    return $ output >>= first ZFSListParseError . A.parseOnly objects 



localCmd :: P.ProcessConfig () () ()
localCmd = P.shell listShellCmd

sshCmd :: SSHSpec -> P.ProcessConfig () () ()
sshCmd spec = P.shell $ "ssh " ++ show spec ++ " " ++ listShellCmd

allOutputs :: P.ProcessConfig () () () -> P.ProcessConfig () (STM LBS.ByteString) (STM LBS.ByteString)
allOutputs command = P.setStdin P.closed $ P.setStdout P.byteStringOutput $ P.setStderr P.byteStringOutput command