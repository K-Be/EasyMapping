//
//  EKRelationshipMapping.m
//  EasyMappingExample
//
//  Created by Denys Telezhkin on 14.06.14.
//  Copyright (c) 2014 EasyKit. All rights reserved.
//

#import "EKRelationshipMapping.h"


@interface EKRelationshipMapping ()

@property (nonatomic, strong) EKObjectMapping* strongRefMapping;
@property (nonatomic, weak) EKObjectMapping* weakRefMapping;

@end


@implementation EKRelationshipMapping


+ (instancetype)relationshipMappingWithRecursiveMapping:(EKObjectMapping*)objectMapping
{
	EKRelationshipMapping* relationship = [[EKRelationshipMapping alloc] init];
	relationship.weakRefMapping = objectMapping;
	
	return relationship;
}


+ (instancetype)relationshipMappingWithOwnMapping:(EKObjectMapping*)objectMapping
{
	EKRelationshipMapping* relationship = [[EKRelationshipMapping alloc] init];
	relationship.strongRefMapping = objectMapping;
	
	return relationship;
}


- (EKObjectMapping*)objectMapping
{
	EKObjectMapping* mapping = self.weakRefMapping;
	if (self.strongRefMapping)
	{
		mapping = self.strongRefMapping;
	}
	
	return mapping;
}


- (void)setObjectMapping:(EKObjectMapping *)objectMapping
{
	self.strongRefMapping = objectMapping;
	self.weakRefMapping = nil;
}

@end
