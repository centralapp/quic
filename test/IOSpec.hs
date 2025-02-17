{-# LANGUAGE OverloadedStrings #-}

module IOSpec where

import Control.Monad
import qualified Data.ByteString as BS
import Test.Hspec
import UnliftIO.Concurrent
import qualified UnliftIO.Exception as E

import Network.QUIC
import qualified Network.QUIC.Client as C
import Network.QUIC.Internal
import Network.QUIC.Server

import Config

spec :: Spec
spec = do
    sc0 <- runIO makeTestServerConfigR
    var <- runIO newEmptyMVar
    let sc = sc0 { scHooks = (scHooks sc0) {
                         onServerReady = putMVar var ()
                       }
                   }
    let cc = testClientConfigR
    let waitS = takeMVar var :: IO ()
    describe "send & recv" $ do
        it "can exchange data on random dropping" $ do
            withPipe (Randomly 20) $ testSendRecv cc sc waitS 1000
        it "can exchange data on server 0" $ do
            withPipe (DropServerPacket [0]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 1" $ do
            withPipe (DropServerPacket [1]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 2" $ do
            withPipe (DropServerPacket [2]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 3" $ do
            withPipe (DropServerPacket [3]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 4" $ do
            withPipe (DropServerPacket [4]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 5" $ do
            withPipe (DropServerPacket [5]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 6" $ do
            withPipe (DropServerPacket [6]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 7" $ do
            withPipe (DropServerPacket [7]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 8" $ do
            withPipe (DropServerPacket [8]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 9" $ do
            withPipe (DropServerPacket [9]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 10" $ do
            withPipe (DropServerPacket [10]) $ testSendRecv cc sc waitS 20
        it "can exchange data on server 11" $ do
            withPipe (DropServerPacket [11]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 0" $ do
            withPipe (DropClientPacket [0]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 1" $ do
            withPipe (DropClientPacket [1]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 2" $ do
            withPipe (DropClientPacket [2]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 3" $ do
            withPipe (DropClientPacket [3]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 4" $ do
            withPipe (DropClientPacket [4]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 5" $ do
            withPipe (DropClientPacket [5]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 6" $ do
            withPipe (DropClientPacket [6]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 7" $ do
            withPipe (DropClientPacket [7]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 8" $ do
            withPipe (DropClientPacket [8]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 9" $ do
            withPipe (DropClientPacket [9]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 10" $ do
            withPipe (DropClientPacket [10]) $ testSendRecv cc sc waitS 20
        it "can exchange data on client 11" $ do
            withPipe (DropClientPacket [11]) $ testSendRecv cc sc waitS 20
    describe "recvStream" $ do
        -- https://github.com/kazu-yamamoto/quic/pull/54
        it "don't block if client stop sending first" $ do
            withPipe (Randomly 20) $ testRecvStreamClientStopFirst cc sc waitS
        it "don't block if server stop sending first" $ do
            withPipe (Randomly 20) $ testRecvStreamServerStopFirst cc sc waitS

consumeBytes :: Stream -> Int -> IO ()
consumeBytes _ 0 = return ()
consumeBytes strm left = do
    bs <- recvStream strm 1024
    when (BS.null bs) $ expectationFailure "no enough bytes received"
    let len = BS.length bs
    when (len > left) $ expectationFailure "extra bytes received"
    consumeBytes strm (left - len)

assertEndOfStream :: Stream -> IO ()
assertEndOfStream strm = recvStream strm 1024 `shouldReturn` ""

testRecvStreamClientStopFirst :: C.ClientConfig -> ServerConfig -> IO () -> IO ()
testRecvStreamClientStopFirst cc sc waitS = do
    mvar <- newEmptyMVar
    E.bracket (forkIO $ server mvar) killThread $ \_ -> client mvar
  where
    aerr = ApplicationProtocolError 0

    client mvar = do
        waitS
        C.run cc $ \conn -> do
            strm <- stream conn
            sendStream strm (BS.replicate 10000 0)
            takeMVar mvar `shouldReturn` ()
            stopStream strm aerr
            resetStream strm aerr
            takeMVar mvar `shouldReturn` ()
    server mvar = run sc $ \conn -> do
        strm <- acceptStream conn
        consumeBytes strm 10000 `shouldReturn` ()
        -- notify client to stop stream after all bytes are received.
        putMVar mvar ()
        -- verify that recvStream does not block
        assertEndOfStream strm
        putMVar mvar ()

testRecvStreamServerStopFirst :: C.ClientConfig -> ServerConfig -> IO () -> IO ()
testRecvStreamServerStopFirst cc sc waitS = do
    mvar <- newEmptyMVar
    E.bracket (forkIO $ server mvar) killThread $ \_ -> client mvar
  where
    aerr = ApplicationProtocolError 0

    client mvar = do
        waitS
        C.run cc $ \conn -> do
            strm <- stream conn
            sendStream strm (BS.replicate 10000 0)
            takeMVar mvar `shouldReturn` ()
    server mvar = run sc $ \conn -> do
        strm <- acceptStream conn
        consumeBytes strm 10000 `shouldReturn` ()
        -- ask client to stop sending.
        stopStream strm aerr
        -- verify that recvStream does not block
        assertEndOfStream strm
        resetStream strm aerr
        putMVar mvar ()

testSendRecv :: C.ClientConfig -> ServerConfig -> IO () -> Int -> IO ()
testSendRecv cc sc waitS times = do
    mvar <- newEmptyMVar
    E.bracket (forkIO $ server mvar) killThread $ \_ -> client mvar
  where
    client mvar = do
        waitS
        C.run cc $ \conn -> do
            strm <- stream conn
            let bs = BS.replicate 10000 0
            replicateM_ times $ sendStream strm bs
            shutdownStream strm
            takeMVar mvar `shouldReturn` ()
    server mvar = run sc $ \conn -> do
        strm <- acceptStream conn
        consumeBytes strm (10000 * times)
        assertEndOfStream strm
        putMVar mvar ()
