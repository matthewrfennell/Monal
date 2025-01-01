//
//  DataLayerMigrations.h
//  monalxmpp
//
//  Created by Friedrich Altheide on 15.01.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLSQLite.h"
#import "MLDataLayer.h"

NS_ASSUME_NONNULL_BEGIN

@interface DataLayerMigrations : NSObject

+(BOOL) migrateDB:(MLSQLite*) db withMLDataLayer:(MLDataLayer*) MLDataLayer;

@end

NS_ASSUME_NONNULL_END
