//
//  EKWTool.h
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define ekw_completeBlock(obj) !complete?:complete(obj);

#define PREFiX @"wke_"
#define ekw_tableNameKey @"ekw_tableName"

#define ekw_uniqueKeysSelector NSSelectorFromString(@"ekw_uniqueKeys")
#define ekw_ignoreKeysSelector NSSelectorFromString(@"ekw_ignoreKeys")
#define ekw_unionPrimaryKeysSelector NSSelectorFromString(@"ekw_unionPrimaryKeys")

typedef NS_ENUM(NSInteger,ekw_getModelInfoType){//过滤数据类型
    ekw_ModelInfoInsert,//插入过滤
    ekw_ModelInfoSingleUpdate,//单条更新过滤
    ekw_ModelInfoArrayUpdate,//批量更新过滤
    ekw_ModelInfoNone//无过滤
};

@interface EKWTool : NSObject

/**
 如果表格不存在就新建.
 */
+(BOOL)ifNotExistWillCreateTableWithObject:(id _Nonnull)object ignoredKeys:(NSArray* const _Nullable)ignoredKeys;

/**
 根据对象获取要更新或插入的字典.
 */
+(NSDictionary* _Nonnull)getDictWithObject:(id _Nonnull)object ignoredKeys:(NSArray* const _Nullable)ignoredKeys filtModelInfoType:(ekw_getModelInfoType)filtModelInfoType;

#pragma mark - 用于查询
//转换从数据库中读取出来的数据.
+(NSArray*_Nullable)tansformDataFromSqlDataWithTableName:(NSString*_Nullable)tableName class:(__unsafe_unretained _Nonnull Class)cla array:(NSArray*_Nullable)array;

#pragma mark -
//跟value和数据类型type 和编解码标志 返回编码插入数据库的值,或解码数据库的值.
+(id _Nullable )getSqlValue:(id _Nullable )value type:(NSString*_Nullable)type encode:(BOOL)encode;

#pragma mark - 智能刷新数据库 调用的方法
/**
 根据类获取变量名列表
 @onlyKey YES:紧紧返回key,NO:在key后面添加type.
 */
+(NSArray *_Nullable)getClassIvarList:(__unsafe_unretained Class _Nullable )cla Object:(_Nullable id)object onlyKey:(BOOL)onlyKey;

#pragma mark - Base Tool Method
/**
 判断并获取字段类型
 */
+(NSString *_Nullable)keyAndType:(NSString *_Nullable)param;

/**
 根据传入的对象获取表名.
 */
+(NSString *_Nullable)getTableNameWithObject:(id _Nullable )object;

/**
 判断是不是 "唯一约束" 字段.
 */
+(BOOL)isUniqueKey:(NSString *_Nullable)uniqueKey with:(NSString *_Nullable)param;

/**
 过滤建表的key.
 */
+(NSArray *_Nullable)filtCreateKeys:(NSArray *_Nullable)ekw_createkeys ignoredkeys:(NSArray *_Nullable)ekw_ignoredkeys;

/**
 判断类是否实现了某个类方法.
 */
+(id _Nullable)executeSelector:(SEL _Nullable)selector forClass:(Class _Nullable )cla;

@end
