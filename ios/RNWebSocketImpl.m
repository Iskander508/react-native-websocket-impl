/**
 * Copyright (c) 2015-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RNWebSocketImpl.h"

#import <objc/runtime.h>

#import <React/RCTConvert.h>
#import <React/RCTUtils.h>

#import "RCTSRWebSocket.h"

@implementation RCTWSImplWebSocket (React)

- (NSNumber *)reactTag
{
  return objc_getAssociatedObject(self, _cmd);
}

- (void)setReactTag:(NSNumber *)reactTag
{
  objc_setAssociatedObject(self, @selector(reactTag), reactTag, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end

@interface RCTWSImplWebSocketModule () <RCTWSImplWebSocketDelegate>

@end

@implementation RCTWSImplWebSocketModule
{
  NSMutableDictionary<NSNumber *, RCTWSImplWebSocket *> *_sockets;
  NSMutableDictionary<NSNumber *, id<RCTWSImplWebSocketContentHandler>> *_contentHandlers;
}

RCT_EXPORT_MODULE(WebSocketImpl)

// Used by RCTBlobModule
@synthesize methodQueue = _methodQueue;

- (NSArray *)supportedEvents
{
  return @[@"ws-impl-message",
           @"ws-impl-open",
           @"ws-impl-error",
           @"ws-impl-close"];
}

- (void)invalidate
{
  _contentHandlers = nil;
  for (RCTWSImplWebSocket *socket in _sockets.allValues) {
    socket.delegate = nil;
    [socket close];
  }
}

RCT_EXPORT_METHOD(connect:(NSURL *)URL protocols:(NSArray *)protocols options:(NSDictionary *)options socketID:(nonnull NSNumber *)socketID)
{
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];

  // We load cookies from sharedHTTPCookieStorage (shared with XHR and
  // fetch). To get secure cookies for wss URLs, replace wss with https
  // in the URL.
  NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:true];
  if ([components.scheme.lowercaseString isEqualToString:@"wss"]) {
    components.scheme = @"https";
  }

  // Load supplied headers
  [options[@"headers"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
    [request addValue:[RCTConvert NSString:value] forHTTPHeaderField:key];
  }];

  RCTWSImplWebSocket *webSocket = [[RCTWSImplWebSocket alloc] initWithURLRequest:request protocols:protocols];
  [webSocket setDelegateDispatchQueue:_methodQueue];
  webSocket.delegate = self;
  webSocket.reactTag = socketID;
  if (!_sockets) {
    _sockets = [NSMutableDictionary new];
  }
  _sockets[socketID] = webSocket;
  [webSocket open];
}

RCT_EXPORT_METHOD(send:(nonnull NSNumber *)socketID usingMessage:(NSString *)message)
{
  [_sockets[socketID] send:message];
}

RCT_EXPORT_METHOD(sendBinary:(NSString *)base64String forSocketID:(nonnull NSNumber *)socketID)
{
  [self sendData:[[NSData alloc] initWithBase64EncodedString:base64String options:0] forSocketID:socketID];
}

- (void)sendData:(NSData *)data forSocketID:(nonnull NSNumber *)socketID
{
  [_sockets[socketID] send:data];
}

RCT_EXPORT_METHOD(ping:(nonnull NSNumber *)socketID)
{
  [_sockets[socketID] sendPing:NULL];
}

RCT_EXPORT_METHOD(pong:(nonnull NSNumber *)socketID)
{
  [_sockets[socketID] sendPong:NULL];
}

RCT_EXPORT_METHOD(close:(nonnull NSNumber *)socketID withCode:(NSInteger)code reason:(NSString *)reason)
{
  [_sockets[socketID] closeWithCode:code reason:reason];
  [_sockets removeObjectForKey:socketID];
}

- (void)setContentHandler:(id<RCTWSImplWebSocketContentHandler>)handler forSocketID:(NSString *)socketID
{
  if (!_contentHandlers) {
    _contentHandlers = [NSMutableDictionary new];
  }
  _contentHandlers[socketID] = handler;
}

#pragma mark - RCTWSImplWebSocketDelegate methods

- (void)webSocket:(RCTWSImplWebSocket *)webSocket didReceiveMessage:(id)message
{
  NSString *type;

  NSNumber *socketID = [webSocket reactTag];
  id contentHandler = _contentHandlers[socketID];
  if (contentHandler) {
    message = [contentHandler processWebsocketMessage:message forSocketID:socketID withType:&type];
  } else {
    if ([message isKindOfClass:[NSData class]]) {
      type = @"binary";
      message = [message base64EncodedStringWithOptions:0];
    } else {
      type = @"text";
    }
  }

  [self sendEventWithName:@"ws-impl-message" body:@{
    @"message": message,
    @"type": type,
    @"index": webSocket.reactTag
  }];
}

- (void)webSocketDidOpen:(RCTWSImplWebSocket *)webSocket
{
  [self sendEventWithName:@"ws-impl-open" body:@{
    @"index": webSocket.reactTag
  }];
}

- (void)webSocket:(RCTWSImplWebSocket *)webSocket didFailWithError:(NSError *)error
{
  NSNumber *socketID = [webSocket reactTag];
  _contentHandlers[socketID] = nil;
  _sockets[socketID] = nil;
  [self sendEventWithName:@"ws-impl-error" body:@{
    @"message": error.localizedDescription,
    @"index": socketID
  }];
}

- (void)webSocket:(RCTWSImplWebSocket *)webSocket
 didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason
         wasClean:(BOOL)wasClean
{
  NSNumber *socketID = [webSocket reactTag];
  _contentHandlers[socketID] = nil;
  _sockets[socketID] = nil;
  [self sendEventWithName:@"ws-impl-close" body:@{
    @"code": @(code),
    @"reason": RCTNullIfNil(reason),
    @"clean": @(wasClean),
    @"index": socketID
  }];
}

@end

@implementation RCTBridge (RCTWSImplWebSocketModule)

- (RCTWSImplWebSocketModule *)webSocketModule
{
  return [self moduleForClass:[RCTWSImplWebSocketModule class]];
}

@end
