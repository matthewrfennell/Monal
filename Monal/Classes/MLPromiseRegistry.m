//
//  MLPromiseRegistry.m
//  monalxmpp
//
//  Created by Matthew Fennell on 29/09/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "HelperTools.h"
#import "MLPromiseRegistry.h"

NS_ASSUME_NONNULL_BEGIN

@implementation MLSerializablePromise

-(instancetype) init
{
    _uuid = [NSUUID UUID];
    _isResolved = false;
    return self;
}

-(void) resolve:(id _Nullable) arg
{
    _resolveArg = arg;
    _isResolved = true;
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:_uuid forKey:@"uuid"];
    [coder encodeObject:_resolveArg forKey:@"resolveArg"];
    [coder encodeBool:_isResolved forKey:@"isResolved"];
}

-(nullable instancetype) initWithCoder:(NSCoder*) coder
{
    self = [self init];
    _uuid = [coder decodeObjectForKey:@"uuid"];
    _resolveArg = [coder decodeObjectForKey:@"resolveArg"];
    _isResolved = [coder decodeBoolForKey:@"isResolved"];
    return self;
}

@end

@interface MLPromise()

@property(nonatomic, strong) MLSerializablePromise* serializablePromise;

@property(nonatomic, weak) MLPromiseRegistry* promiseRegistry;

@property(nonatomic, strong) PromiseResolverCallback promiseResolverCallback;
@property(nonatomic, strong) PMKResolver onConsumeCallback;

@property(nonatomic, strong) AnyPromise* promise;

@end

@implementation MLPromise

-(instancetype) initWithCallback:(PromiseResolverCallback) promiseResolverCallback andPromiseRegistry:(MLPromiseRegistry*) promiseRegistry
{
    _serializablePromise = [MLSerializablePromise new];
    _promiseResolverCallback = promiseResolverCallback;
    _promiseRegistry = promiseRegistry;
    [promiseRegistry addPromise:self];
    return self;
}

-(instancetype) initWithSerializablePromise:(MLSerializablePromise*) serializablePromise andPromiseRegistry:(MLPromiseRegistry*) promiseRegistry
{
    _serializablePromise = serializablePromise;
    _promiseResolverCallback = ^(NSUUID* uuid) {};
    _onConsumeCallback = ^(PMKResolver resolve) {};
    _promiseRegistry = promiseRegistry;
    [promiseRegistry addPromise:self];
    return self;
}

-(instancetype) initEmptyPromiseWithPromiseRegistry:(MLPromiseRegistry*) promiseRegistry
{
    _serializablePromise = [MLSerializablePromise new];
    _promiseResolverCallback = ^(NSUUID* uuid) {};
    _onConsumeCallback = ^(PMKResolver resolve) {};
    _promiseRegistry = promiseRegistry;
    [_promiseRegistry addPromise:self];
    return self;
}

-(NSUUID*) uuid
{
    return _serializablePromise.uuid;
}

-(id) resolveArg
{
    return _serializablePromise.resolveArg;
}

-(BOOL) isResolved
{
    return _serializablePromise.isResolved;
}

-(void) resolve:(id _Nullable) arg
{
    DDLogDebug(@"Resolving promise %@ with arg %@", self.uuid, arg);
    NSAssert(!self.isResolved, @"Trying to resolve an already resolved promise");

    [_serializablePromise resolve:arg];
    [self attemptConsume];
}

-(AnyPromise*) toPromise
{
    DDLogDebug(@"Converting MLPromise %@ to AnyPromise", self.uuid);

    if(_promise != nil)
    {
        DDLogDebug(@"Returning already existing AnyPromise");
        return _promise;
    }

    _promise = [AnyPromise promiseWithResolverBlock:^(PMKResolver onConsumeCallback) {
        self.onConsumeCallback = onConsumeCallback;
        self.promiseResolverCallback(self.uuid);
    }];

    return _promise;
}

-(void) attemptConsume
{
    DDLogDebug(@"Intend to consume promise %@ with arg %@", self.uuid, self.resolveArg);

    if([HelperTools isAppExtension])
    {
        DDLogDebug(@"Not consuming promise %@ as we are in the app extension", self.uuid);
    }

    if(!self.isResolved) {
        DDLogDebug(@"Not consuming promise %@ as it has not been resolved yet", self.uuid);
        return;
    }

    _onConsumeCallback(self.resolveArg);
    [_promiseRegistry removePromise:self.uuid];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:_serializablePromise forKey:@"serializablePromise"];
}

-(nullable instancetype) initWithCoder:(NSCoder*) coder
{
    self = [self init];
    _serializablePromise = [coder decodeObjectForKey:@"serializablePromise"];
    return self;
}

@end

@interface MLPromiseRegistry()

@property(atomic, strong) NSMutableDictionary<NSUUID*, MLPromise*>* promises;

@end

@implementation MLPromiseRegistry

-(instancetype) init
{
    _promises = [NSMutableDictionary new];
    return self;
}

-(NSUUID*) addPromise:(MLPromise*) promise
{
    [_promises setObject:promise forKey:promise.uuid];
    DDLogDebug(@"After adding %@, promise map contains: %@", promise.uuid, [_promises allKeys]);
    return promise.uuid;
}

-(void) removePromise:(NSUUID*) uuid
{
    [_promises removeObjectForKey:uuid];
    DDLogDebug(@"After removing %@, promise map contains: %@", uuid, [_promises allKeys]);
}

-(MLPromise*) getPromise:(NSUUID*) uuid
{
    DDLogDebug(@"Getting promise %@, promise map contains: %@", uuid, [_promises allKeys]);
    MLPromise* promise = _promises[uuid];
    if(promise == nil)
    {
        DDLogError(@"Tried to get promise %@ which does not exist. Returning empty promise", uuid);
        return [[MLPromise alloc] initEmptyPromiseWithPromiseRegistry:self];
    }
    return promise;
}

-(void) attemptConsumeRemainingPromises
{
    for(MLPromise* promise in [_promises allValues])
    {
        [promise attemptConsume];
    }
}

-(void) sync:(MLPromiseRegistry*) other
{
    DDLogDebug(@"Syncing our promises %@ with their promises %@", [_promises allKeys], [other.promises allKeys]);
    for(MLPromise* otherPromise in [other.promises allValues])
    {
        if(_promises[otherPromise.uuid] != nil)
        {
            _promises[otherPromise.uuid].serializablePromise = otherPromise.serializablePromise;
        }
        else
        {
            _promises[otherPromise.uuid] = [[MLPromise alloc] initWithSerializablePromise:otherPromise.serializablePromise andPromiseRegistry:self];
        }
    }
    DDLogDebug(@"Promises after sync: %@", [_promises allKeys]);
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:_promises forKey:@"promises"];
}

-(nullable instancetype) initWithCoder:(NSCoder*) coder
{
    self = [self init];
    _promises = [coder decodeObjectForKey:@"promises"];
    return self;
}

@end

NS_ASSUME_NONNULL_END
