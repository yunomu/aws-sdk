-- | aws-sdk is an AWS library for Haskell
--
-- Put your AWS AccessKey and SecretAccessKey into a configuration
-- file. Write the following in /./\//aws.config/.
--
-- > accessKey: your-access-key
-- > secretAccessKey: your-secret-access-key
--
-- The following is quick example(DescribeInstances).
--
-- > module Example where
-- > 
-- > import Data.Conduit
-- > import qualified Data.Conduit.List as CL
-- > import Control.Monad.IO.Class (liftIO)
-- > import Control.Monad.Trans.Class (lift)
-- > 
-- > import AWS
-- > import AWS.EC2
-- > 
-- > main :: IO ()
-- > main = do
-- >     cred <- loadCredential
-- >     doc <- runResourceT $ do
-- >         ctx <- liftIO $ newEC2Context cred
-- >         runEC2 ctx $ do
-- >             response <- describeInstances [] []
-- >             lift $ response $$ CL.consume
-- >     print doc
-- >     putStr "Length: "
-- >     print $ length doc
{-# LANGUAGE OverloadedStrings #-}
module AWS
    ( -- * Credentials
      Credential
    , loadCredential
    ) where

import AWS.Credential
