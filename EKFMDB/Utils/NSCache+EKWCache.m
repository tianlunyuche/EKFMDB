//
//  NSCache+EKWCache.m
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#import "NSCache+EKWCache.h"

@implementation NSCache (EKWCache)

+(instancetype)ekw_cache {
    static dispatch_once_t onceToken;
    static NSCache* keyCaches;
    dispatch_once(&onceToken, ^{
        keyCaches = [[NSCache alloc] init];
    });
    return keyCaches;
}


@end
