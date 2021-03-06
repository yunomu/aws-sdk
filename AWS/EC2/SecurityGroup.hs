{-# LANGUAGE FlexibleContexts, RankNTypes #-}

module AWS.EC2.SecurityGroup
    ( describeSecurityGroups
    , createSecurityGroup
    , deleteSecurityGroup
    , authorizeSecurityGroupIngress
    , authorizeSecurityGroupEgress
    , revokeSecurityGroupIngress
    , revokeSecurityGroupEgress
    ) where

import Data.Text (Text)
import Data.ByteString (ByteString)

import Data.XML.Types (Event)
import Data.Conduit
import Control.Monad.Trans.Control (MonadBaseControl)
import Control.Applicative
import Data.Monoid

import AWS.EC2.Internal
import AWS.EC2.Types
import AWS.EC2.Query
import AWS.Lib.Parser
import AWS.Util

describeSecurityGroups
    :: (MonadResource m, MonadBaseControl IO m)
    => [Text] -- ^ GroupNames
    -> [Text] -- ^ GroupIds
    -> [Filter] -- ^ Filters
    -> EC2 m (ResumableSource m SecurityGroup)
describeSecurityGroups names ids filters =
    ec2QuerySource "DescribeSecurityGroups" params
    $ itemConduit "securityGroupInfo" $
        SecurityGroup
        <$> getT "ownerId"
        <*> getT "groupId"
        <*> getT "groupName"
        <*> getT "groupDescription"
        <*> getT "vpcId"
        <*> ipPermissionsSink "ipPermissions"
        <*> ipPermissionsSink "ipPermissionsEgress"
        <*> resourceTagSink
  where
    params =
        [ ArrayParams "GroupName" names
        , ArrayParams "GroupId" ids
        , FilterParams filters
        ]

ipPermissionsSink :: MonadThrow m
    => Text -> GLSink Event m [IpPermission]
ipPermissionsSink name = itemsSet name $ IpPermission
    <$> getT "ipProtocol"
    <*> getT "fromPort"
    <*> getT "toPort"
    <*> itemsSet "groups" (
        UserIdGroupPair
        <$> getT "userId"
        <*> getT "groupId"
        <*> getT "groupName"
        )
    <*> itemsSet "ipRanges" (getT "cidrIp")

createSecurityGroup
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ GroupName
    -> Text -- ^ GroupDescription
    -> Maybe Text -- ^ VpcId
    -> EC2 m (Maybe Text) -- ^ GroupId
createSecurityGroup name desc vpc =
    ec2Query "CreateSecurityGroup" params
        $ getT_ "return" *> getT "groupId"
  where
    params =
        [ ValueParam "GroupName" name
        , ValueParam "GroupDescription" desc
        ] ++ maybe [] (\a -> [ValueParam "VpcId" a]) vpc

deleteSecurityGroup
    :: (MonadResource m, MonadBaseControl IO m)
    => SecurityGroupRequest
    -> EC2 m Bool
deleteSecurityGroup param =
    ec2Query "DeleteSecurityGroup" [p param] $ getT "return"

p :: SecurityGroupRequest -> QueryParam
p (SecurityGroupRequestGroupId t)   = ValueParam "GroupId" t
p (SecurityGroupRequestGroupName t) = ValueParam "GroupName" t

-- | not tested
authorizeSecurityGroupIngress
    :: (MonadResource m, MonadBaseControl IO m)
    => SecurityGroupRequest
    -> [IpPermission]
    -> EC2 m Bool
authorizeSecurityGroupIngress =
    securityGroupQuery "AuthorizeSecurityGroupIngress"

-- | not tested
authorizeSecurityGroupEgress
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ GroupId
    -> [IpPermission]
    -> EC2 m Bool
authorizeSecurityGroupEgress gid =
    securityGroupQuery "AuthorizeSecurityGroupEgress"
        $ SecurityGroupRequestGroupId gid

-- | not tested
revokeSecurityGroupIngress
    :: (MonadResource m, MonadBaseControl IO m)
    => SecurityGroupRequest
    -> [IpPermission]
    -> EC2 m Bool
revokeSecurityGroupIngress =
    securityGroupQuery "RevokeSecurityGroupIngress"

-- | not tested
revokeSecurityGroupEgress
    :: (MonadResource m, MonadBaseControl IO m)
    => Text -- ^ GroupId
    -> [IpPermission]
    -> EC2 m Bool
revokeSecurityGroupEgress gid =
    securityGroupQuery "RevokeSecurityGroupEgress"
        $ SecurityGroupRequestGroupId gid

securityGroupQuery
    :: (MonadResource m, MonadBaseControl IO m)
    => ByteString -- ^ Action
    -> SecurityGroupRequest
    -> [IpPermission]
    -> EC2 m Bool
securityGroupQuery act param ipps =
    ec2Query act params $ getT "return"
  where
    params = [p param]
        ++ concatMap (uncurry ipPermissionParam) (zip intstr ipps)

intstr :: [Int]
intstr = [1..]

ipPermissionParam :: Int -> IpPermission -> [QueryParam]
ipPermissionParam num ipp =
    [ValueParam (pre <> ".IpProtocol") $
        ipPermissionIpProtocol ipp]
    ++ (uncurry (mk pre) =<<
        [ (".FromPort", toText <$> ipPermissionFromPort ipp)
        , (".ToPort", toText <$> ipPermissionToPort ipp)
        ])
    ++ map
        (uncurry ipr)
        (zip intstr $ ipPermissionIpRanges ipp)
    ++ concatMap
        (uncurry grp)
        (zip intstr $ ipPermissionGroups ipp)
  where
    pre = "IpPermissions." <> toText num
    mk h name = maybe [] (\a -> [ValueParam (h <> name) a])
    grph n = pre <> ".Groups." <> toText n
    grp n g = 
        [ ValueParam (grph n <> ".GroupId") $
            userIdGroupPairGroupId g
        ] ++ (uncurry (mk (grph n)) =<<
            [ (".UserId", userIdGroupPairUserId g)
            , (".GroupName", userIdGroupPairGroupName g)
            ])
    ipr n r = ValueParam
        (pre <> ".IPRanges." <> toText n <> ".CidrIp")
        $ toText r
