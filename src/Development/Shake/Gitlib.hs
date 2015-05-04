{-# LANGUAGE OverloadedStrings, DeriveDataTypeable, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleInstances #-}
module Development.Shake.Gitlib
    ( defaultRuleGitLib
    , getGitContents
    , doesGitFileExist
    , readGitFile
    ) where

import System.IO
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Functor
import Data.Maybe


import Development.Shake
import Development.Shake.Rule
import Development.Shake.Classes

import Git
import Git.Libgit2
import Data.Tagged

type RepoPath = FilePath


-- I do not want a new dependency just for these, so this is copied from text-binary
instance Binary T.Text where
    put = put . T.encodeUtf8
    get = T.decodeUtf8 <$> get



newtype GetGitReferenceQ = GetGitReferenceQ (RepoPath, RefName)
    deriving (Typeable,Eq,Hashable,Binary,NFData,Show)

newtype GitSHA = GitSHA T.Text
    deriving (Typeable,Eq,Hashable,Binary,NFData,Show)

newtype GetGitFileRefQ = GetGitFileRefQ (RepoPath, T.Text, FilePath)
    deriving (Typeable,Eq,Hashable,Binary,NFData,Show)

instance Rule GetGitReferenceQ GitSHA where
    storedValue _ (GetGitReferenceQ (repoPath, name)) =
        Just . GitSHA <$> getGitReference' repoPath name

instance Rule GetGitFileRefQ (Maybe T.Text) where
    storedValue _ (GetGitFileRefQ (repoPath, ref', filename)) =
        Just <$> getGitFileRef' repoPath ref' filename

getGitContents :: RepoPath -> Action [FilePath]
getGitContents repoPath = do
    GitSHA ref' <- apply1 $ GetGitReferenceQ (repoPath, "HEAD")
    liftIO $ withRepository lgFactory repoPath $ do
        ref <- parseOid ref'
        commit <- lookupCommit (Tagged ref)
        tree <- lookupTree (commitTree commit)
        entries <- listTreeEntries tree
        return $ map (BS.unpack . fst) entries

getGitReference' :: RepoPath -> RefName -> IO T.Text
getGitReference' repoPath refName = do
    withRepository lgFactory repoPath $ do
        Just ref <- resolveReference refName
        return $ renderOid ref

getGitFileRef' :: RepoPath -> T.Text -> FilePath -> IO (Maybe T.Text)
getGitFileRef' repoPath ref' fn = do
    withRepository lgFactory repoPath $ do
        ref <- parseOid ref'
        commit <- lookupCommit (Tagged ref)
        tree <- lookupTree (commitTree commit)
        entry <- treeEntry tree (BS.pack fn)
        case entry of
            Just (BlobEntry ref _) -> return $ Just $ renderObjOid ref
            _ -> return Nothing

doesGitFileExist :: RepoPath -> FilePath -> Action Bool
doesGitFileExist repoPath fn = do
    GitSHA ref' <- apply1 $ GetGitReferenceQ (repoPath, "HEAD")
    res <- apply1 $ GetGitFileRefQ (repoPath, ref', fn)
    return $ isJust (res :: Maybe T.Text)

readGitFile :: FilePath -> FilePath -> Action BS.ByteString
readGitFile repoPath fn = do
    GitSHA ref' <- apply1 $ GetGitReferenceQ (repoPath, "HEAD")
    res <- apply1 $ GetGitFileRefQ (repoPath, ref', fn)
    case res of
        Nothing -> fail "readGitFile: File does not exist"
        Just ref' -> liftIO $ withRepository lgFactory repoPath $ do
            ref <- parseOid ref'
            catBlob (Tagged ref)

defaultRuleGitLib :: Rules ()
defaultRuleGitLib = do
    rule $ \(GetGitReferenceQ (repoPath, refName)) -> Just $ liftIO $
        GitSHA <$> getGitReference' repoPath refName
    rule $ \(GetGitFileRefQ (repoPath, ref', fn)) -> Just $ liftIO $
        getGitFileRef' repoPath ref' fn

