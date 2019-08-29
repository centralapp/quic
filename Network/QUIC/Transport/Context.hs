{-# LANGUAGE OverloadedStrings #-}

module Network.QUIC.Transport.Context where

import Data.IORef
-- import Data.ByteString
import qualified Network.TLS as TLS

import Network.QUIC.TLS
import Network.QUIC.Transport.Types

data Role = Client TLS.ClientParams
          | Server TLS.ServerParams

data Context = Context {
    role :: Role
  , tlsConetxt        :: TLS.Context
  , myCID             :: CID
  , initialSecret     :: (Secret, Secret)
  , peerCID           :: IORef CID
  , usedCipher        :: IORef Cipher
  , earlySecret       :: IORef (Maybe (TLS.SecretTriple TLS.EarlySecret))
  , handshakeSecret   :: IORef (Maybe (TLS.SecretTriple TLS.HandshakeSecret))
  , applicationSecret :: IORef (Maybe (TLS.SecretTriple TLS.ApplicationSecret))
  -- intentionally using the single space for packet numbers.
  , packetNumber      :: IORef PacketNumber
  }

emptyCID :: CID
emptyCID = CID ""

clientContext :: Version -> TLS.HostName -> CID -> IO Context
clientContext ver hostname cid = do
    (tlsctx, cparams) <- tlsClientContext hostname
    let cis = clientInitialSecret ver cid
        sis = serverInitialSecret ver cid
    Context (Client cparams) tlsctx cid (cis, sis) <$> newIORef emptyCID <*> newIORef defaultCipher <*> newIORef Nothing <*> newIORef Nothing <*> newIORef Nothing <*> newIORef 0

serverContext :: Version -> FilePath -> FilePath -> CID -> IO Context
serverContext ver key cert cid = do
    (tlsctx, sparams) <- tlsServerContext key cert
    let cis = clientInitialSecret ver cid
        sis = serverInitialSecret ver cid
    Context (Server sparams) tlsctx cid (cis, sis) <$> newIORef emptyCID <*> newIORef defaultCipher <*> newIORef Nothing <*> newIORef Nothing <*> newIORef Nothing <*> newIORef 0

tlsClientParams :: Context -> TLS.ClientParams
tlsClientParams ctx = case role ctx of
  Client cparams -> cparams
  Server _       -> error "tlsClientParams"

tlsServerParams :: Context -> TLS.ServerParams
tlsServerParams ctx = case role ctx of
  Server sparams -> sparams
  Client _       -> error "tlsServerParams"

getCipher :: Context -> IO Cipher
getCipher ctx = readIORef (usedCipher ctx)

setCipher :: Context -> Cipher -> IO ()
setCipher ctx cipher = writeIORef (usedCipher ctx) cipher

txInitialSecret :: Context -> Secret
txInitialSecret ctx = case role ctx of
    Client _ -> cis
    Server _ -> sis
  where
    (cis, sis) = initialSecret ctx

rxInitialSecret :: Context -> Secret
rxInitialSecret ctx = case role ctx of
    Client _ -> sis
    Server _ -> cis
  where
    (cis, sis) = initialSecret ctx

txHandshakeSecret :: Context -> IO Secret
txHandshakeSecret ctx = do
    Just st <- readIORef (handshakeSecret ctx)
    case role ctx of
      Client _ -> let TLS.ClientTrafficSecret s = TLS.triClient st
                  in return $ Secret s
      Server _ -> let TLS.ServerTrafficSecret s = TLS.triServer st
                  in return $ Secret s

rxHandshakeSecret :: Context -> IO Secret
rxHandshakeSecret ctx = do
    Just st <- readIORef (handshakeSecret ctx)
    case role ctx of
      Client _ -> let TLS.ServerTrafficSecret s = TLS.triServer st
                  in return $ Secret s
      Server _ -> let TLS.ClientTrafficSecret s = TLS.triClient st
                  in return $ Secret s

txApplicationSecret :: Context -> IO Secret
txApplicationSecret ctx = do
    Just st <- readIORef (applicationSecret ctx)
    case role ctx of
      Client _ -> let TLS.ClientTrafficSecret s = TLS.triClient st
                  in return $ Secret s
      Server _ -> let TLS.ServerTrafficSecret s = TLS.triServer st
                  in return $ Secret s

rxApplicationSecret :: Context -> IO Secret
rxApplicationSecret ctx = do
    Just st <- readIORef (applicationSecret ctx)
    case role ctx of
      Client _ -> let TLS.ServerTrafficSecret s = TLS.triServer st
                  in return $ Secret s
      Server _ -> let TLS.ClientTrafficSecret s = TLS.triClient st
                  in return $ Secret s