//
//  EasyMapping
//
//  Copyright (c) 2012-2014 Lucas Medeiros.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "EKCoreDataImporter.h"
#import "EKPropertyHelper.h"
#import "NSArray+FlattenArray.h"

@interface EKCoreDataImporter ()
@property (nonatomic, strong) NSSet * entityNames;

// Keys are entity names, values - NSSet with primary keys
@property (nonatomic, strong) NSDictionary * existingEntitiesPrimaryKeys;

// Keys are entity names, values - NSDictionary, where keys = primary keys, values = fetched objects
@property (nonatomic, strong) NSMutableDictionary * fetchedExistingEntities;

@end

@implementation EKCoreDataImporter

+ (instancetype)importerWithMapping:(EKManagedObjectMapping *)mapping
             externalRepresentation:(id)externalRepresentation
                            context:(NSManagedObjectContext *)context
{
    EKCoreDataImporter * importer = [self new];

    importer.mapping = mapping;
    importer.externalRepresentation = externalRepresentation;
    importer.context = context;

    importer.fetchedExistingEntities = [NSMutableDictionary dictionary];
    [importer collectEntityNames];
    [importer inspectRepresentation];

    return importer;
}

#pragma mark - collect entity names

- (void)collectEntityNames
{
    NSMutableSet * entityNames = [NSMutableSet set];

    [self collectEntityNamesRecursively:entityNames mapping:self.mapping];

    self.entityNames = [entityNames copy];
}

- (void)collectEntityNamesRecursively:(NSMutableSet *)entityNames mapping:(EKManagedObjectMapping *)mapping
{
    [entityNames addObject:mapping.entityName];

    for (EKManagedObjectMapping * oneMapping in [mapping.hasOneMappings allValues])
    {
        [self collectEntityNamesRecursively:entityNames mapping:oneMapping];
    }

    for (EKManagedObjectMapping * manyMapping in [mapping.hasManyMappings allValues])
    {
        [self collectEntityNamesRecursively:entityNames mapping:manyMapping];
    }
}

#pragma mark - Inspecting representation

- (void)inspectRepresentation
{
    NSMutableDictionary * existingPrimaryKeys = [NSMutableDictionary dictionary];
    for (NSString * entityName in self.entityNames)
    {
        existingPrimaryKeys[entityName] = [NSSet set];
    }
    [self inspectRepresentation:self.externalRepresentation
                   usingMapping:self.mapping
               accumulateInside:existingPrimaryKeys];

    self.existingEntitiesPrimaryKeys = [existingPrimaryKeys copy];
}

- (void)inspectRepresentation:(id)representation
                 usingMapping:(EKManagedObjectMapping *)mapping
             accumulateInside:(NSMutableDictionary *)dictionary
{
    id rootRepresentation = [EKPropertyHelper extractRootPathFromExternalRepresentation:representation
                                                                            withMapping:mapping];
    if ([rootRepresentation isKindOfClass:[NSArray class]])
    {
        for (NSDictionary * objectInfo in rootRepresentation)
        {
            id value = [self primaryKeyValueFromRepresentation:objectInfo usingMapping:mapping];
            if (value && value != (id)[NSNull null])
            {
                dictionary[mapping.entityName] = [dictionary[mapping.entityName] setByAddingObject:value];
            }
        }
    }
    else if ([rootRepresentation isKindOfClass:[NSDictionary class]])
    {
        id value = [self primaryKeyValueFromRepresentation:rootRepresentation usingMapping:mapping];
        if (value && value != (id)[NSNull null])
        {
            dictionary[mapping.entityName] = [dictionary[mapping.entityName] setByAddingObject:value];
        }
    }

    [mapping.hasOneMappings enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL * stop)
    {
        NSDictionary * oneMappingRepresentation = [rootRepresentation valueForKeyPath:key];
        if (![oneMappingRepresentation isEqual:[NSNull null]])
        {
            [self inspectRepresentation:oneMappingRepresentation
                           usingMapping:obj
                       accumulateInside:dictionary];
        }
    }];

    [mapping.hasManyMappings enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL * stop)
    {
        NSArray * manyMappingRepresentation = [rootRepresentation valueForKeyPath:key];

        if (![manyMappingRepresentation isEqual:[NSNull null]])
        {
            // This is needed, because if one of the objects in array does not contain object for key, returned structure would be something like this:
            //
            // @[<null>,@[value2,value3]]
            //
            // And we are interested in flat structure like this: @[value2,value3]
            manyMappingRepresentation = [manyMappingRepresentation ek_flattenedArray];

            [self inspectRepresentation:manyMappingRepresentation
                           usingMapping:obj
                       accumulateInside:dictionary];
        }
    }];
}

- (id)primaryKeyValueFromRepresentation:(id)representation usingMapping:(EKManagedObjectMapping *)mapping
{
    EKFieldMapping * primaryKeyMapping = [mapping primaryKeyFieldMapping];
    id primaryValue = [EKPropertyHelper getValueOfField:primaryKeyMapping
                                     fromRepresentation:representation];
    return primaryValue;
}

#pragma mark - Fetching existing objects

- (NSMutableDictionary *)fetchExistingObjectsForMapping:(EKManagedObjectMapping *)mapping
{
    NSSet * lookupValues = self.existingEntitiesPrimaryKeys[mapping.entityName];
    if (lookupValues.count == 0) return [NSMutableDictionary dictionary];

    NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:mapping.entityName];
    NSPredicate * predicate = [NSPredicate predicateWithFormat:@"%K IN %@", mapping.primaryKey, lookupValues];
    [fetchRequest setPredicate:predicate];
    [fetchRequest setFetchLimit:lookupValues.count];

    NSMutableDictionary * output = [NSMutableDictionary new];
    NSArray * existingObjects = [self.context executeFetchRequest:fetchRequest error:NULL];
    for (NSManagedObject * object in existingObjects)
    {
        output[[object valueForKey:mapping.primaryKey]] = object;
    }

    return output;
}

- (NSMutableDictionary *)cachedObjectsForMapping:(EKManagedObjectMapping *)mapping
{
    NSMutableDictionary * entityObjectsMap = self.fetchedExistingEntities[mapping.entityName];
    if (!entityObjectsMap)
    {
        entityObjectsMap = [self fetchExistingObjectsForMapping:mapping];
        self.fetchedExistingEntities[mapping.entityName] = entityObjectsMap;
    }

    return entityObjectsMap;
}

- (id)existingObjectForRepresentation:(id)representation mapping:(EKManagedObjectMapping *)mapping
{
    NSDictionary * entityObjectsMap = [self cachedObjectsForMapping:mapping];

    id primaryKeyValue = [EKPropertyHelper getValueOfField:[mapping primaryKeyFieldMapping]
                                        fromRepresentation:representation];
    if (primaryKeyValue == nil || primaryKeyValue == NSNull.null) return nil;

    return entityObjectsMap[primaryKeyValue];
}

@end
