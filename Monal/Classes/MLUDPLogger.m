//
//  MLUDPLogger.m
//  monalxmpp
//
//  Created by Thilo Molitor on 17.08.20.
//  Copyright © 2020 Monal.im. All rights reserved.
//  Based on this gist: https://gist.github.com/ratulSharker/3b6bce0debe77fd96344e14566b23e06
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <Network/Network.h>
#import <zlib.h>
#import "MLUDPLogger.h"
#import "HelperTools.h"
#import "AESGcm.h"
#import "MLXMPPManager.h"
#import "MLContact.h"
#import "xmpp.h"

DDLoggerName const DDLoggerNameUDP = @"monal.loggger.udp.mainQueue";

static NSData* _key;
static volatile MLUDPLogger* _self;

@interface MLUDPLogger ()
{
    volatile nw_connection_t _connection;
    volatile dispatch_queue_t _send_queue;
    volatile NSCondition* _send_condition;
    volatile nw_error_t _last_error;
    volatile u_int64_t _counter;
}
+(void) logError:(NSString*) format, ... NS_FORMAT_FUNCTION(1, 2);
@end


@implementation MLUDPLogger

+(void) initialize
{
    //hash raw key string with sha256 to get the correct 256 bit length needed for AES-256
    //WARNING: THIS DOES NOT ENHANCE ENTROPY!! PLEASE MAKE SURE TO USE A KEY WITH PROPER ENTROPY!!
    NSData* rawKey = [[[HelperTools defaultsDB] stringForKey:@"udpLoggerKey"] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* key = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(rawKey.bytes, (unsigned int)rawKey.length, key.mutableBytes);
    _key = [key copy];
}

+(void) flushWithTimeout:(double) timeout
{
    if(_self != nil)
    {
        NSCondition* condition = [NSCondition new];
        //this timeout will trigger if the flush could not be finished in time (leeway of 10ms)
        //use dispatch_source_set_timer() directly instead of createTimer() because we don't want to log anything in here
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, (uint64_t)(0.010 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, ^{
            [[self class] logError:@"flush timer triggered!"];
            dispatch_source_cancel(timer);
            [condition lock];
            [condition signal];
            [condition unlock];
        });
        dispatch_resume(timer);
        //this block will be executed if all prior blocks managed to send out their messages (e.g. queue is flushed)
        dispatch_async(_self->_send_queue, ^{
            [[self class] logError:@"flush succeeded in time"];
            dispatch_source_cancel(timer);      //stop timer
            [condition lock];
            [condition signal];
            [condition unlock];
        });
        //wait for either timeout or flush to trigger
        [condition lock];
        [condition wait];
        [condition unlock];
    }
}

+(void) directlyWriteLogMessage:(DDLogMessage*) logMessage
{
    if(_self == nil)
    {
        [[self class] logError:@"Ignoring call to directlySyncWriteLogMessage: _self still nil!"];
        return;
    }
    return [_self realLogMessage:logMessage wasDirect:YES];
}

-(void) dealloc
{
    _self = nil;
}

-(void) didAddLogger
{
    _self = self;
    _send_condition = [NSCondition new];
    _send_queue = dispatch_queue_create("MLUDPLoggerInternalSendQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
}

-(void) willRemoveLogger
{
    _self = nil;
}


-(DDLoggerName) loggerName
{
    return DDLoggerNameUDP;
}

+(void) logError:(NSString*) format, ... NS_FORMAT_FUNCTION(1, 2)
{
#ifdef IS_ALPHA
    va_list args;
    va_start(args, format);
    NSString* message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"MLUDPLogger: %@", message);
    
    /*
    //log error in 250ms
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.250*NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              (uint64_t)0);
    dispatch_source_set_event_handler(timer, ^{
        DDLogError(@"%@", message);
    });
    */
#endif
}

//code taken from here: https://stackoverflow.com/a/11389847/3528174
-(NSData*) gzipDeflate:(NSData*) data
{
    if([data length] == 0)
        return data;

    z_stream strm;

    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.total_out = 0;
    strm.next_in = (Bytef*)[data bytes];
    strm.avail_in = (unsigned int)[data length];

    // Compresssion Levels:
    //   Z_NO_COMPRESSION
    //   Z_BEST_SPEED
    //   Z_BEST_COMPRESSION
    //   Z_DEFAULT_COMPRESSION
    if(deflateInit2(&strm, Z_BEST_COMPRESSION, Z_DEFLATED, (15+16), 8, Z_DEFAULT_STRATEGY) != Z_OK)
    {
        [[self class] logError:@"gzipDeflate error"];
        return nil;
    }

    NSMutableData* compressed = [NSMutableData dataWithLength:16384];   // 16K chunks for expansion
    do {
        if(strm.total_out >= [compressed length])
            [compressed increaseLengthBy:16384];
        strm.next_out = [compressed mutableBytes] + strm.total_out;
        strm.avail_out = (unsigned int)([compressed length] - strm.total_out);
        deflate(&strm, Z_FINISH);  
    } while(strm.avail_out == 0);
    deflateEnd(&strm);

    [compressed setLength:strm.total_out];
    return compressed;
}

-(void) disconnect
{
    if(_connection != NULL)
        nw_connection_force_cancel(_connection);
    _connection = NULL;
    [_send_condition lock];
    [_send_condition signal];
    [_send_condition unlock];
}

-(void) createConnectionIfNeeded
{
    if(_connection == NULL)
    {
        __block NSCondition* condition = [NSCondition new];
        
        nw_endpoint_t endpoint = nw_endpoint_create_host([[[HelperTools defaultsDB] stringForKey:@"udpLoggerHostname"] cStringUsingEncoding:NSUTF8StringEncoding], [[[HelperTools defaultsDB] stringForKey:@"udpLoggerPort"] cStringUsingEncoding:NSUTF8StringEncoding]);
        nw_parameters_t parameters = nw_parameters_create_secure_udp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        
        _connection = nw_connection_create(endpoint, parameters);
        nw_connection_set_queue(_connection, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        nw_connection_set_state_changed_handler(_connection, ^(nw_connection_state_t state, nw_error_t error) {
            if(state == nw_connection_state_ready)
            {
                [condition lock];
                [condition signal];
                [condition unlock];
            }
            //udp connections should be "established" in way less than 100ms, so unlock this (dispatch) queue after 100ms
            //the connection blocking longer mostly happens if the device has no connectivity (state waiting)
            else if(state == nw_connection_state_waiting || state == nw_connection_state_preparing)
            {
                usleep(100000);
                [condition lock];
                [condition signal];
                [condition unlock];
            }
            //retry in all error cases
            else if(state == nw_connection_state_failed || state == nw_connection_state_cancelled || state == nw_connection_state_invalid)
            {
                self->_last_error = error;
                [[self class] logError:@"connect error: %@", error];
                self->_connection = NULL;
                [condition lock];
                [condition signal];
                [condition unlock];
                [self->_send_condition lock];
                [self->_send_condition signal];
                [self->_send_condition unlock];
            }
        });
        [condition lock];
        nw_connection_start(_connection);
        [condition wait];
        [condition unlock];
        
        //try again if we did not succeed
        if(_connection == NULL)
        {
            [[self class] logError:@"retrying connection start..."];
            [self createConnectionIfNeeded];
        }
    }
}

-(void) logMessage:(DDLogMessage*) logMessage
{
    return [self realLogMessage:logMessage wasDirect:NO];
}

-(void) realLogMessage:(DDLogMessage*) logMessage wasDirect:(BOOL) direct
{
    static uint64_t counter = 0;
    
    //early return if deactivated
    if(![[HelperTools defaultsDB] boolForKey: @"udpLoggerEnabled"])
        return;
    
    //ignore log messages already udp-logged as direct messages when handling queued messages
    if(!direct && logMessage.ml_isDirect)
        return;
    
    NSError* error = nil; 
    NSData* rawData = [HelperTools convertLogmessageToJsonData:logMessage counter:&counter andError:&error];
    if(error != nil || rawData == nil)
    {
        [[self class] logError:@"json encode error: %@", error];
        return;
    }
    
    //compress data to account for udp size limits
    rawData = [self gzipDeflate:rawData];
    
    //encrypt rawData using the "derived" key (see warning above!)
    MLEncryptedPayload* payload = [AESGcm encrypt:rawData withKey:_key];
    NSMutableData* data  = [NSMutableData dataWithData:payload.iv];
    [data appendData:payload.authTag];
    [data appendData:payload.body];
    
    if(data.length > 65000)
        [[self class] logError:@"not sending message, too big: %lu", (unsigned long)data.length];
    else
        dispatch_async(_send_queue, ^{
            [self sendData:data withOriginalMessage:logMessage->_message];
        });
}

-(void) sendData:(NSData*) data withOriginalMessage:(NSString*) msg
{
    [self createConnectionIfNeeded];
    
    //the call to dispatch_get_main_queue() is a dummy because we are using DISPATCH_DATA_DESTRUCTOR_DEFAULT which is performed inline
    [_send_condition lock];
    nw_connection_send(_connection, dispatch_data_create(data.bytes, data.length, dispatch_get_main_queue(), DISPATCH_DATA_DESTRUCTOR_DEFAULT), NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t  _Nullable error) {
        self->_last_error = error;
        if(error != NULL)
        {
            //NSError* st_error = (NSError*)CFBridgingRelease(nw_error_copy_cf_error(error));
            [[self class] logError:@"send error: %@\n%@", error, msg];
            
        }
        //[[self class] logError:@"unlocking send condition (%@)...", [NSNumber numberWithUnsignedLongLong:self->_counter]];
        [self->_send_condition lock];
        [self->_send_condition signal];
        [self->_send_condition unlock];
    });
    //block this queue until our udp message was sent or an error occured
    [_send_condition wait];
    [_send_condition unlock];
    if(_last_error != NULL)
    {
        //don't retry if message was too long
        if([@"Message too long" isEqualToString:[NSString stringWithFormat:@"%@", _last_error]])
            return;
        //retry
        //[self disconnect];
        [[self class] logError:@"retrying sendData with error: %@", _last_error];
        [self sendData:data withOriginalMessage:msg];
    }
}

@end
