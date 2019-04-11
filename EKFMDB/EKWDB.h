//
//  EKWDB.h
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "EKWDBConfig.h"
#import "FMDB.h"

@interface EKWDB : NSObject

//信号量.
@property(nonatomic, strong)dispatch_semaphore_t _Nullable semaphore;

/**
 设置操作过程中不可关闭数据库(即closeDB函数无效).
 */
@property(nonatomic,assign)BOOL disableCloseDB;

/**
 自定义数据库名称
 */
@property(nonatomic,copy)NSString* _Nonnull sqliteName;

/**
 获取单例函数.
 */
+(_Nonnull instancetype)shareManager;

#pragma mark - 查询
/**
 查询对象.
 */
-(void)queryObjectWithTableName:(NSString* _Nonnull)tablename class:(__unsafe_unretained _Nonnull Class)cla where:(NSString* _Nullable)where complete:(ekw_complete_A)complete;

/**
 直接传入条件sql语句查询
 */
-(void)queryWithTableName:(NSString* _Nonnull)name conditions:(NSString* _Nullable)conditions complete:(ekw_complete_A)complete;

#pragma mark - 删除
-(void)deleteWithTableName:(NSString* _Nonnull)name conditions:(NSString* _Nullable)conditions complete:(ekw_complete_B)complete;

#pragma mark - 批量插入
/**
 批量插入或更新
 */
-(void)ekw_saveOrUpateArray:(NSArray* _Nonnull)array ignoredKeys:(NSArray* const _Nullable)ignoredKeys complete:(ekw_complete_B)complete;

/**
 创建表(如果存在则不创建).
 */
-(void)createTableWithTableName:(NSString* _Nonnull)name keys:(NSArray<NSString*>* _Nonnull)keys unionPrimaryKeys:(NSArray* _Nullable)unionPrimaryKeys uniqueKeys:(NSArray* _Nullable)uniqueKeys complete:(ekw_complete_B)complete;

/**
 存储一个对象.
 @object 将要存储的对象.
 @ignoreKeys 忽略掉模型中的哪些key(即模型变量)不要存储,nil时全部存储.
 @complete 回调的block.
 */
-(void)saveObject:(id _Nonnull)object ignoredKeys:(NSArray* const _Nullable)ignoredKeys complete:(ekw_complete_B)complete;

/**
 数据库中是否存在表.
 */
-(void)isExistWithTableName:(NSString* _Nonnull)name complete:(ekw_complete_B)complete;

#pragma mark - 操作FMDB的方法层
/**
 关闭数据库.
 */
-(void)closeDB;

@end
