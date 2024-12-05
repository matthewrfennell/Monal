//
//  MLPromiseRegistry.h
//  Monal
//
//  Created by Matthew Fennell on 29/09/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

#import "MLConstants.h"

NS_ASSUME_NONNULL_BEGIN

@class MLPromiseRegistry;
typedef void (^PromiseResolverCallback)(NSUUID*);

@interface MLSerializablePromise : NSObject <NSSecureCoding>

@property(readonly, strong) NSUUID* uuid;
@property(nonatomic, strong) id resolveArg;
@property(nonatomic, assign) BOOL isResolved;

-(void) resolve:(id _Nullable) arg;

@end

@interface MLPromise : NSObject <NSSecureCoding>

-(instancetype) initWithCallback:(PromiseResolverCallback) promiseResolverCallback andPromiseRegistry:(MLPromiseRegistry*) promiseRegisry;
-(instancetype) initEmptyPromiseWithPromiseRegistry:(MLPromiseRegistry*) promiseRegistry;
-(instancetype) initWithSerializablePromise:(MLSerializablePromise*) serializablePromise andPromiseRegistry:(MLPromiseRegistry*) promiseRegistry;

-(void) resolve:(id _Nullable) arg;
-(AnyPromise*) toPromise;
-(void) attemptConsume;

@end

@interface MLPromiseRegistry : NSObject <NSSecureCoding>

-(NSUUID*) addPromise:(MLPromise*) promise;
-(void) removePromise:(NSUUID*) uuid;
-(MLPromise*) getPromise:(NSUUID*) uuid;
-(void) attemptConsumeRemainingPromises;
-(void) sync:(MLPromiseRegistry*) other;

@end

NS_ASSUME_NONNULL_END
