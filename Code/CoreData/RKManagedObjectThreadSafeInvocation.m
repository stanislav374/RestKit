//
//  RKManagedObjectThreadSafeInvocation.m
//  RestKit
//
//  Created by Blake Watters on 5/12/11.
//  Copyright (c) 2009-2012 RestKit. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "RKManagedObjectThreadSafeInvocation.h"

@interface RKManagedObjectThreadSafeInvocation ()
@property (nonatomic, retain) NSMutableDictionary *argumentKeyPaths;
@end

@implementation RKManagedObjectThreadSafeInvocation

@synthesize managedObjectContext = _managedObjectContext;
@synthesize argumentKeyPaths = _argumentKeyPaths;

+ (RKManagedObjectThreadSafeInvocation *)invocationWithMethodSignature:(NSMethodSignature *)methodSignature
{
    return (RKManagedObjectThreadSafeInvocation *)[super invocationWithMethodSignature:methodSignature];
}

- (void)setManagedObjectKeyPaths:(NSSet *)keyPaths forArgument:(NSInteger)index
{
    if (nil == _argumentKeyPaths) {
        self.argumentKeyPaths = [NSMutableDictionary dictionary];
    }

    NSNumber *argumentIndex = [NSNumber numberWithInteger:index];
    [self.argumentKeyPaths setObject:keyPaths forKey:argumentIndex];
}

- (void)setValue:(id)value forKeyPathOrKey:(NSString *)keyPath object:(id)object
{
    [object setValue:value forKeyPath:keyPath];

    id testValue = [object valueForKeyPath:keyPath];
    if (![value isEqual:testValue]) {
        [object setValue:value forKey:keyPath];
        testValue = [object valueForKeyPath:keyPath];

        NSAssert([value isEqual:testValue], @"Could not set value");
    }
}

- (void)serializeManagedObjectsForArgument:(id)argument withKeyPaths:(NSSet *)keyPaths
{
    for (NSString *keyPath in keyPaths) {
        id value = [argument valueForKeyPath:keyPath];
        if ([value isKindOfClass:[NSManagedObject class]]) {
            NSManagedObjectID *objectID = [(NSManagedObject *)value objectID];
            NSLog(@"^^^ Serializing object %@ with ID %@", value, objectID);
            [self setValue:objectID forKeyPathOrKey:keyPath object:argument];
        } else if ([value respondsToSelector:@selector(allObjects)]) {
            id collection = [[[[[value class] alloc] init] autorelease] mutableCopy];
            NSLog(@"Serializing objects in collection %@", value);
            for (id subObject in value) {
                NSLog(@"Serializing %@", subObject);
                if ([subObject isKindOfClass:[NSManagedObject class]]) {
                    [collection addObject:[(NSManagedObject *)subObject objectID]];
                    NSLog(@"^^^ Serializing object %@ with ID %@. isTemporary = %d. moc = %@", subObject, [subObject objectID], [[subObject objectID] isTemporaryID], [subObject managedObjectContext]);
                } else {
                    [collection addObject:subObject];
                }
            }
            
            NSLog(@"Setting value %@ for keyPath %@ on object %@", collection, keyPath, argument);
            [self setValue:collection forKeyPathOrKey:keyPath object:argument];
            [collection release];
        }
    }
}

- (void)deserializeManagedObjectIDsForArgument:(id)argument withKeyPaths:(NSSet *)keyPaths
{
    NSAssert(self.managedObjectContext, @"Managed object context cannot be nil");
    NSLog(@"Deserializing argument %@ with keyPaths %@", argument, keyPaths);
    for (NSString* keyPath in keyPaths) {
        id value = [argument valueForKeyPath:keyPath];
        NSLog(@"*** Found value %@ to deserialize", value);
        if ([value isKindOfClass:[NSManagedObjectID class]]) {
            __block NSManagedObject *managedObject = nil;
            [self.managedObjectContext performBlockAndWait:^{
                managedObject = [self.managedObjectContext objectWithID:(NSManagedObjectID*)value];
            }];
//            NSManagedObject* managedObject = [self.managedObjectContext objectWithID:(NSManagedObjectID*)value];
            NSLog(@"!!! Found managed object %@ for ID %@", managedObject, value);
            NSAssert(managedObject, @"Expected managed object for ID %@, got nil", value);
            [self setValue:managedObject forKeyPathOrKey:keyPath object:argument];
        } else if ([value respondsToSelector:@selector(allObjects)]) {
            id collection = [[[[[value class] alloc] init] autorelease] mutableCopy];
            NSLog(@"Deserializing array of managed object ID's: %@", value);
            for (id subObject in value) {
                if ([subObject isKindOfClass:[NSManagedObjectID class]]) {
                    __block NSManagedObject *managedObject = nil;
                    [self.managedObjectContext performBlockAndWait:^{
                        managedObject = [self.managedObjectContext objectWithID:(NSManagedObjectID*)subObject];
                    }];
                    [managedObject performSelector:@selector(amenityID)];
                    NSLog(@"--> Found managed object %@ for ID %@", managedObject, subObject);
                    [collection addObject:managedObject];
                } else {
                    [collection addObject:subObject];
                }
            }
            

            [self setValue:collection forKeyPathOrKey:keyPath object:argument];
            [collection release];
        }
    }
}

- (void)serializeManagedObjects
{
    for (NSNumber* argumentIndex in _argumentKeyPaths) {
        NSSet* managedKeyPaths = [_argumentKeyPaths objectForKey:argumentIndex];
        id argument = nil;
        [self getArgument:&argument atIndex:[argumentIndex intValue]];
        if (argument) {
            [self serializeManagedObjectsForArgument:argument withKeyPaths:managedKeyPaths];
        }
    }
}

- (void)deserializeManagedObjects
{
    for (NSNumber *argumentIndex in _argumentKeyPaths) {
        NSSet *managedKeyPaths = [_argumentKeyPaths objectForKey:argumentIndex];
        id argument = nil;
        [self getArgument:&argument atIndex:[argumentIndex intValue]];
        if (argument) {
            [self deserializeManagedObjectIDsForArgument:argument withKeyPaths:managedKeyPaths];
        }
    }
}

- (void)performInvocationOnMainThread
{
    [self deserializeManagedObjects];
    [self invoke];
}

- (void)invokeOnMainThread
{
    [self serializeManagedObjects];
    if ([NSThread isMainThread]) {
        [self performInvocationOnMainThread];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self performInvocationOnMainThread];
        });
    }
}

- (void)dealloc
{
    [_argumentKeyPaths release];
    [_managedObjectContext release];
    [super dealloc];
}

@end
