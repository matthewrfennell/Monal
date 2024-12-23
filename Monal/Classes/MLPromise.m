//
//  MLPromise.m
//  monalxmpp
//
//  Created by Matthew Fennell on 29/09/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "DataLayer.h"
#import "HelperTools.h"
#import "MLPromise.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLPromise()

-(void) resolve:(id _Nullable) argument;

@property(nonatomic, strong) AnyPromise* anyPromise;
@property(nonatomic, strong) id resolvedArgument;
@property(nonatomic, assign) BOOL isResolved;

@end

@implementation MLPromise

static NSMutableDictionary* _resolvers;

+(void) initialize
{
    _resolvers = [NSMutableDictionary new];
}

-(instancetype) init
{
    self.uuid = [NSUUID UUID];
    self.isResolved = false;

    [self serialize];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deserialize) name:kMonalUnfrozen object:nil];

    DDLogVerbose(@"Initialized promise %@ with uuid %@", self, self.uuid);

    return self;
}

-(nullable instancetype) initWithCoder:(NSCoder*) coder
{
    self.uuid = [coder decodeObjectForKey:@"uuid"];
    self.resolvedArgument = [coder decodeObjectForKey:@"resolvedArgument"];
    self.isResolved = [coder decodeBoolForKey:@"isResolved"];
    DDLogVerbose(@"Initialised from coder a promise %@ with uuid %@", self, self.uuid);
    return self;
}

-(void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    DDLogVerbose(@"Deallocated promise %@ with uuid %@", self, self.uuid);
}

-(void) serialize
{
    [[DataLayer sharedInstance] addPromise:self];
    DDLogVerbose(@"Serialized promise %@ with uuid %@", self, self.uuid);
}

-(void) deserialize
{
    MLPromise* dbPromise = [[DataLayer sharedInstance] getPromise:self];
    self.resolvedArgument = dbPromise.resolvedArgument;
    self.isResolved = dbPromise.isResolved;
    DDLogVerbose(@"Deserialized promise %@ with uuid %@", self, self.uuid);

    [self attemptConsume];
}

-(void) resolve:(id _Nullable) argument
{
    DDLogDebug(@"Resolving promise %@ with uuid %@ and argument %@", self, self.uuid, argument);
    NSAssert(!self.isResolved, @"Trying to resolve an already resolved promise");

    self.resolvedArgument = argument;
    self.isResolved = true;
    [self serialize];
    [self attemptConsume];
}

-(void) fulfill:(id _Nullable) argument
{
    [self resolve:argument];
}

-(void) reject:(NSError*) error
{
    [self resolve:error];
}

-(AnyPromise*) toAnyPromise
{
    DDLogDebug(@"Converting promise %@ with uuid %@ to AnyPromise", self, self.uuid);

    if(self.anyPromise != nil)
    {
        DDLogVerbose(@"Returning already existing AnyPromise");
        return self.anyPromise;
    }

    self.anyPromise = [AnyPromise promiseWithResolverBlock:^(PMKResolver resolve) {
        [_resolvers setObject:resolve forKey:self.uuid];
        DDLogVerbose(@"Adding resolver %@ with uuid %@ to resolvers map", resolve, self.uuid);
        DDLogVerbose(@"Resolvers map is now: %@", _resolvers);
    }];

    return self.anyPromise;
}

-(void) attemptConsume
{
    DDLogDebug(@"Intend to consume promise %@ with uuid %@ and argument %@", self, self.uuid, self.resolvedArgument);

    if([HelperTools isAppExtension])
    {
        DDLogDebug(@"Not consuming promise %@ with uuid %@ as we are in the app extension", self, self.uuid);
        return;
    }

    if(!self.isResolved)
    {
        DDLogDebug(@"Not consuming promise %@ with uuid %@ as it has not been resolved yet", self, self.uuid);
        return;
    }

    PMKResolver resolve = _resolvers[self.uuid];

    if(resolve == nil)
    {
        DDLogDebug(@"Tried to consume promise %@ with uuid %@ when there is no resolver available", self, self.uuid);
        return;
    }

    DDLogDebug(@"Resolving promise %@ with uuid %@ and argument %@", self, self.uuid, self.resolvedArgument);
    resolve(self.resolvedArgument);

    [_resolvers removeObjectForKey:self.uuid];
    DDLogVerbose(@"Removed resolver with uuid %@ from resolvers map", self.uuid);
    DDLogVerbose(@"Resolvers map is now: %@", _resolvers);

    [[DataLayer sharedInstance] removePromise:self];
}

+(BOOL) supportsSecureCoding
{
    return YES;
}

-(void) encodeWithCoder:(NSCoder*) coder
{
    [coder encodeObject:self.uuid forKey:@"uuid"];
    [coder encodeObject:self.resolvedArgument forKey:@"resolvedArgument"];
    [coder encodeBool:self.isResolved forKey:@"isResolved"];
}

@end

NS_ASSUME_NONNULL_END
