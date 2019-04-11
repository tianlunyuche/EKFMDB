//
//  NSObject+EKWModel.h
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EKWDBConfig.h"

@protocol EKWProtocol <NSObject>

@optional
/**
 自定义 “唯一约束” 函数,如果需要 “唯一约束”字段,则在类中自己实现该函数.
 @return 返回值是 “唯一约束” 的字段名(即相对应的变量名).
 */
+ (NSArray* _Nonnull)ekw_uniqueKeys;

/**
 @return 返回不需要存储的属性.
 */
+ (NSArray* _Nonnull)ekw_ignoreKeys;

@end

@interface NSObject (EKWModel) <EKWProtocol>

/**
 同步存储.
 */
- (BOOL)ekw_save;

/**
 同步存储或更新.
 当"唯一约束"或"主键"存在时 (数据模型要实现ekw_uniqueKeys 类方法)，此接口会更新旧数据,没有则存储新数据.
 提示：“唯一约束”优先级高于"主键".
 */
- (BOOL)ekw_saveOrUpdate;

/**
 同步查询所有结果.
 */
+ (NSArray* _Nullable)ekw_findAll;

/**
 通过键值获取对象
 
 @param key 键
 @param value 值
 @return 第一个结果
 */
+ (id _Nullable)ekw_findByKey:(NSString *_Nullable)key andValue:(NSString *_Nullable)value;

/**
 @param where
 例子二：查询uid为@"1533026"的 数据，where为：
 [NSString stringWithFormat:@"where %@=%@", ekw_sqlKey(@"uid"), @"1533026"]
 
 例子二：查询name等于爸爸和age等于45,或者name等于马哥的数据，where为：
 [NSString stringWithFormat:@"where %@=%@ and %@=%@ or %@=%@",ekw_sqlKey(@"age"),ekw_sqlValue(@(45)),ekw_sqlKey(@"name"),ekw_sqlValue(@"爸爸"),ekw_sqlKey(@"name"),ekw_sqlValue(@"马哥")];
 @return 查询结果
 */
+ (id _Nullable)ekw_findByWhere:(NSString* _Nullable)where;

/**
 例子一，删除People类中name等于"美国队长"的数据,where 为
 [NSString stringWithFormat:@"where %@=%@",ekw_sqlKey(@"name"),ekw_sqlValue(@"美国队长")];
 
 例子二，删除全部 ，where为 nil
 */
+ (BOOL)ekw_deleteBywhere:(NSString* _Nullable)where;

@end
