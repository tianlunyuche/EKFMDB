//
//  NSObject+EKWModel.m
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#import "NSObject+EKWModel.h"
#import "EKWDB.h"
#import "EKWTool.h"

#define ekw_getIgnoreKeys [EKWTool executeSelector:ekw_ignoreKeysSelector forClass:[self class]]

@implementation NSObject (EKWModel)

/**
 同步存储.
 */
- (BOOL)ekw_save {
    __block BOOL result;
    [[EKWDB shareManager] saveObject:self ignoredKeys:ekw_getIgnoreKeys complete:^(BOOL isSuccess) {
        result = isSuccess;
    }];
    //关闭数据库
    [[EKWDB shareManager] closeDB];
    return result;
}

/**
 同步存储或更新.
 当"唯一约束"或"主键"存在时，此接口会更新旧数据,没有则存储新数据.
 提示：“唯一约束”优先级高于"主键".
 */
- (BOOL)ekw_saveOrUpdate {
    return [[self class] ekw_saveOrUpdateArray:@[self]];
}

/**
 同步 存储或更新 数组元素.
 
 @param array 存放对象的数组.(数组中存放的是同一种类型的数据)
 当"唯一约束"或"主键"存在时，此接口会更新旧数据,没有则存储新数据.
 提示：“唯一约束”优先级高于"主键".
 @return 是否存储或更新 成功
 */
+ (BOOL)ekw_saveOrUpdateArray:(NSArray* _Nonnull)array {
    NSAssert(array && array.count,@"数组没有元素!");
    __block BOOL result;
    [[EKWDB shareManager] ekw_saveOrUpateArray:array ignoredKeys:ekw_getIgnoreKeys complete:^(BOOL isSuccess) {
        result = isSuccess;
    }];
    result ? : NSLog(@"数据库 %@更新失败",[self class]);
    //关闭数据库
    [[EKWDB shareManager] closeDB];
    return result;
}

/**
 同步查询所有结果.
 */
+ (NSArray* _Nullable)ekw_findAll {
    return [[self class] ekw_findAll:nil];
}

/**
 同步查询所有结果.
 @tablename 当此参数为nil时,查询以此类名为表名的数据，非nil时，查询以此参数为表名的数据.
 */
+ (NSArray* _Nullable)ekw_findAll:(NSString* _Nullable)tablename {
    if (tablename == nil) {
        tablename = NSStringFromClass([self class]);
    }
    __block NSArray* results;
    [[EKWDB shareManager] queryObjectWithTableName:tablename class:[self class] where:nil complete:^(NSArray * _Nullable array) {
        results = array;
    }];
    //关闭数据库
    [[EKWDB shareManager] closeDB];
    return results;
}


/**
 通过键值获取对象
 
 @param key 键
 @param value 值
 @return 第一个结果
 */
+ (id _Nullable)ekw_findByKey:(NSString *)key andValue:(NSString *)value {
    if (value) {
        return [[self class] ekw_findByWhere:[NSString stringWithFormat:@"where %@=%@", ekw_sqlKey(key), value]];
    }
    return nil;
}

/**
 @param where
 例子二：查询uid为@"1533026"的 数据，where为：
 [NSString stringWithFormat:@"where %@=%@", ekw_sqlKey(@"uid"), @"1533026"]
 
 例子二：查询name等于爸爸和age等于45,或者name等于马哥的数据，where为：
 [NSString stringWithFormat:@"where %@=%@ and %@=%@ or %@=%@",ekw_sqlKey(@"age"),ekw_sqlValue(@(45)),ekw_sqlKey(@"name"),ekw_sqlValue(@"爸爸"),ekw_sqlKey(@"name"),ekw_sqlValue(@"马哥")];
 @return 查询第一个结果
 */
+ (id _Nullable)ekw_findByWhere:(NSString* _Nullable)where {
    NSArray *objArray = [[self class] ekw_findSetsByWhere:where];
    if (objArray.count) {
        return objArray.firstObject;
    }
    return nil;
}

/**
 @param 同上
 @return 查询所有结果
 */
+ (NSArray* _Nullable)ekw_findSetsByWhere:(NSString* _Nullable)where {
    return [[self class] ekw_find:nil where:where];
}

+ (NSArray* _Nullable)ekw_find:(NSString* _Nullable)tablename where:(NSString* _Nullable)where {
    if(tablename == nil) {
        tablename = NSStringFromClass([self class]);
    }
    __block NSArray* results;
    [[EKWDB shareManager] queryWithTableName:tablename conditions:where complete:^(NSArray * _Nullable array) {
        results = [EKWTool tansformDataFromSqlDataWithTableName:tablename class:[self class] array:array];
    }];
    //关闭数据库
    [[EKWDB shareManager] closeDB];
    return results;
}

/**
 删除People类中name等于"美国队长"的数据,where 为
 [NSString stringWithFormat:@"where %@=%@",ekw_sqlKey(@"name"),ekw_sqlValue(@"美国队长")];
 */
+ (BOOL)ekw_deleteBywhere:(NSString* _Nullable)where {
    return [[self class] ekw_delete:nil where:where];
}

+ (BOOL)ekw_delete:(NSString* _Nullable)tablename where:(NSString* _Nullable)where {
    if(tablename == nil) {
        tablename = NSStringFromClass([self class]);
    }
    __block BOOL result;
    [[EKWDB shareManager] deleteWithTableName:tablename conditions:where complete:^(BOOL isSuccess) {
        result = isSuccess;
    }];
    result ? : NSLog(@"数据库 %@删除失败",[self class]);
    //关闭数据库
    [[EKWDB shareManager] closeDB];
    return result;
}

@end

