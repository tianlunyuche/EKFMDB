//
//  EKWDBConfig.h
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#ifndef EKWDBConfig_h
#define EKWDBConfig_h

#define ekw_primaryKey @"ekw_id"

#define ekw_complete_B void(^_Nullable)(BOOL isSuccess)
#define ekw_complete_I void(^_Nullable)(ekw_dealState result)
#define ekw_complete_A void(^_Nullable)(NSArray* _Nullable array)
#define ekw_changeBlock void(^_Nullable)(bg_changeState result)

typedef NS_ENUM(NSInteger,ekw_dealState){//处理状态
    ekw_error = -1,//处理失败
    ekw_incomplete = 0,//处理不完整
    ekw_complete = 1//处理完整
};

/**
 封装处理传入数据库的key和value.
 */
extern NSString* _Nonnull ekw_sqlKey(NSString* _Nonnull key);
/**
 转换OC对象成数据库数据.
 */
extern NSString* _Nonnull ekw_sqlValue(id _Nonnull value);

#endif /* EKWDBConfig_h */
