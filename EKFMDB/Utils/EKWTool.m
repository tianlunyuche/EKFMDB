//
//  EKWTool.m
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#import "EKWTool.h"
#import "EKWDB.h"
#import "NSCache+EKWCache.h"

#define SqlText @"text" //数据库的字符类型
#define SqlReal @"real" //数据库的浮点类型
#define SqlInteger @"integer" //数据库的整数类型

#define EKWValue @"EKWValue"
#define EKWData @"EKWData"
#define EKWArray @"EKWArray"
#define EKWSet @"EKWSet"
#define EKWDictionary @"EKWDictionary"
#define EKWModel @"EKWModel"
#define EKWMapTable @"EKWMapTable"
#define EKWHashTable @"EKWHashTable"

#define ekw_typeHead_NS @"@\"NS"
#define ekw_typeHead__NS @"@\"__NS"

#define ekw_typeHead_UI @"@\"UI"
#define ekw_typeHead__UI @"@\"__UI"

//100M大小限制.
#define MaxData @(838860800)

/**
 * 遍历所有类的block（父类）
 */
typedef void (^EKWClassesEnumeration)(Class c, BOOL *stop);
static NSSet *foundationClasses_;

@implementation EKWTool

/**
 如果表格不存在就新建.
 */
+(BOOL)ifNotExistWillCreateTableWithObject:(id _Nonnull)object ignoredKeys:(NSArray *const _Nullable)ignoredKeys {
    //检查是否建立了跟对象相对应的数据表
    NSString *tableName = [EKWTool getTableNameWithObject:object];
    //获取"唯一约束"字段名
    NSArray *uniqueKeys = [EKWTool executeSelector:ekw_uniqueKeysSelector forClass:[object class]];
    //zx
    //获取“联合主键”字段名
    //    NSArray *unionPrimaryKeys;
    __block BOOL isExistTable;
    [[EKWDB shareManager] isExistWithTableName:tableName complete:^(BOOL isExist) {
        if (!isExist) { //如果不存在就创建
            NSArray *createKeys = [self filtCreateKeys:[EKWTool getClassIvarList:[object class] Object:object onlyKey:NO] ignoredkeys:ignoredKeys];
            [[EKWDB shareManager] createTableWithTableName:tableName keys:createKeys unionPrimaryKeys:nil uniqueKeys:uniqueKeys complete:^(BOOL isSuccess) {
                isExistTable = isSuccess;
            }];
        }
    }];
    return isExistTable;
}

/**
 根据对象获取要更新或插入的字典.
 */
+(NSDictionary *_Nonnull)getDictWithObject:(id _Nonnull)object ignoredKeys:(NSArray *const _Nullable)ignoredKeys filtModelInfoType:(ekw_getModelInfoType)filtModelInfoType {
    
    //获取存到数据库的数据.
    NSMutableDictionary *valueDict = [self getDictWithObject:object ignoredKeys:ignoredKeys];
    
    if (filtModelInfoType == ekw_ModelInfoSingleUpdate){//单条更新操作时,移除 创建时间和主键 字段不做更新
        //zx
        //判断是否定义了“联合主键”.
        NSArray *unionPrimaryKeys = [EKWTool executeSelector:ekw_unionPrimaryKeysSelector forClass:[object class]];
        NSString *ekw_id = ekw_sqlKey(ekw_primaryKey);
        if(unionPrimaryKeys.count == 0){
            if([valueDict.allKeys containsObject:ekw_id]) {
                [valueDict removeObjectForKey:ekw_id];
            }
        }else{
            if(![valueDict.allKeys containsObject:ekw_id]) {
                valueDict[ekw_id] = @(1);//没有就预备放入
            }
        }
    }else if(filtModelInfoType == ekw_ModelInfoInsert){//插入时要移除主键,不然会出错.
        //判断是否定义了“联合主键”.
        NSArray *unionPrimaryKeys = [EKWTool executeSelector:ekw_unionPrimaryKeysSelector forClass:[object class]];
        NSString *ekw_id = ekw_sqlKey(ekw_primaryKey);
        if(unionPrimaryKeys.count == 0){
            if([valueDict.allKeys containsObject:ekw_id]) {
                [valueDict removeObjectForKey:ekw_id];
            }
        }else{
            if(![valueDict.allKeys containsObject:ekw_id]) {
                valueDict[ekw_id] = @(1);//没有就预备放入
            }
        }
    }else if(filtModelInfoType == ekw_ModelInfoArrayUpdate){//批量更新操作时,移除 创建时间 字段不做更新
        //zx
    }else;
    
    //zx
    NSString *depth_model_conditions = @"\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\";
    [valueDict enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL  *_Nonnull stop) {
        if([obj isKindOfClass:[NSString class]] && [obj containsString:depth_model_conditions]){
            if ([obj containsString:EKWModel]) {
                obj = [obj stringByReplacingOccurrencesOfString:depth_model_conditions withString:@"^*"];
                obj = [obj stringByReplacingOccurrencesOfString:@"^*^*^*^*^*^*^*^*^*^*" withString:@"$#"];
                obj = [obj stringByReplacingOccurrencesOfString:@"$#$#$#$#$#" withString:@"~-"];
                valueDict[key] = [obj stringByReplacingOccurrencesOfString:@"~-~-~-" withString:@"+&"];
            }
        }
    }];
    
    return valueDict;
}

/**
 获取存储数据
 */
+(NSMutableDictionary*)getDictWithObject:(id)object ignoredKeys:(NSArray *const)ignoredKeys {
    NSMutableDictionary *modelInfoDictM = [NSMutableDictionary dictionary];
    NSArray *keyAndTypes = [EKWTool getClassIvarList:[object class] Object:object onlyKey:NO];
    for (NSString *keyAndType in keyAndTypes) {
        NSArray *keyTypes = [keyAndType componentsSeparatedByString:@"*"];
        NSString *propertyName = keyTypes[0];
        NSString *propertyType = keyTypes[1];
        
        if (![ignoredKeys containsObject:propertyName]) {
            //加前缀 是为了防止和数据库关键字发生冲突.
            NSString *sqlColumnName = [NSString stringWithFormat:@"%@%@", PREFiX, propertyName];
            
            id propertyValue;
            id sqlValue;
            //zx
            if (![propertyName isEqualToString:ekw_primaryKey]) {
                propertyValue = [object valueForKey:propertyName];
            }
            if (propertyValue) {
                //列值
                sqlValue = [EKWTool getSqlValue:propertyValue type:propertyType encode:YES];
                modelInfoDictM[sqlColumnName] = sqlValue;
            }
        }
    }
    NSAssert(modelInfoDictM.allKeys.count, @"对象变量数据为空,不能存储!");
    return modelInfoDictM;
}

#pragma mark - 用于查询
//转换从数据库中读取出来的数据.
+(NSArray*)tansformDataFromSqlDataWithTableName:(NSString*)tableName class:(__unsafe_unretained _Nonnull Class)cla array:(NSArray*)array {
    //如果传入的class为空，则直接以字典的形式返回.
    if(cla == nil){
        return array;
    }
    
    NSMutableArray* arrM = [NSMutableArray array];
    for(NSMutableDictionary* dict in array){
        
        // 压缩深层嵌套模型数据量使用
        NSString* depth_model_conditions = @"\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\";
        [dict enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            if([obj isKindOfClass:[NSString class]] && ([obj containsString:@"+&"]||
                                                        [obj containsString:@"~-"]||[obj containsString:@"$#"]||[obj containsString:@"^*"])){
                if ([obj containsString:EKWModel]) {
                    obj = [obj stringByReplacingOccurrencesOfString:@"+&" withString:@"~-~-~-"];
                    obj = [obj stringByReplacingOccurrencesOfString:@"~-" withString:@"$#$#$#$#$#"];
                    obj = [obj stringByReplacingOccurrencesOfString:@"$#" withString:@"^*^*^*^*^*^*^*^*^*^*"];
                    dict[key] = [obj stringByReplacingOccurrencesOfString:@"^*" withString:depth_model_conditions];
                }
            }
        }];
        
        id object = [EKWTool objectFromJsonStringWithTableName:tableName class:cla valueDict:dict];
        [arrM addObject:object];
    }
    return arrM;
}

#pragma mark -
//跟value和数据类型type 和编解码标志 返回编码插入数据库的值,或解码数据库的值.
+(id) getSqlValue:(id)value type:(NSString*)type encode:(BOOL)encode {
    //zx
    if(!value || [value isKindOfClass:[NSNull class]])return nil;
    
    if(([type hasPrefix:ekw_typeHead_NS]||[type hasPrefix:ekw_typeHead__NS])&&[type containsString:@"String"]){
        if([type containsString:@"AttributedString"]){//处理富文本.
            if(encode) {
                return [self archivedDataWithRootObject:value];
            }else{
                return [self unarchivedObjectOfType:type fromValue:value];
            }
        }else{
            return value;
        }
    }else if(([type hasPrefix:ekw_typeHead_NS]||[type hasPrefix:ekw_typeHead__NS])&&[type containsString:@"Number"]){
        if(encode) {
            return [NSString stringWithFormat:@"%@",value];
        }else{
            return [[NSNumberFormatter new] numberFromString:value];
        }
    }else if(([type hasPrefix:ekw_typeHead_NS]||[type hasPrefix:ekw_typeHead__NS])&&[type containsString:@"Array"]){
        if(encode){
            return [self jsonStringWithArray:value];
        }else{
            return [self arrayFromJsonString:value];
        }
    }else if(([type hasPrefix:ekw_typeHead_NS]||[type hasPrefix:ekw_typeHead__NS])&&[type containsString:@"Dictionary"]){
        if(encode){
            return [self jsonStringWithDictionary:value];
        }else{
            return [self dictionaryFromJsonString:value];
        }
    }else if(([type hasPrefix:ekw_typeHead_NS]||[type hasPrefix:ekw_typeHead__NS])&&[type containsString:@"Set"]){
        if(encode){
            return [self jsonStringWithArray:value];
        }else{
            return [self arrayFromJsonString:value];
        }
    }else if(([type hasPrefix:ekw_typeHead_NS]||[type hasPrefix:ekw_typeHead__NS])&&[type containsString:@"Data"]){
        if(encode){
            NSData* data = value;
            NSNumber* maxLength = MaxData;
            NSAssert(data.length<maxLength.integerValue,@"最大存储限制为100M");
            return [data base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        }else{
            return [[NSData alloc] initWithBase64EncodedString:value options:NSDataBase64DecodingIgnoreUnknownCharacters];
        }
    }else if(([type hasPrefix:ekw_typeHead_NS]||[type hasPrefix:ekw_typeHead__NS])&&[type containsString:@"URL"]){
        if(encode){
            return [value absoluteString];
        }else{
            return [NSURL URLWithString:value];
        }
    }else if(([type hasPrefix:ekw_typeHead_UI]||[type hasPrefix:ekw_typeHead__UI])&&[type containsString:@"Image"]){
        if(encode){
            NSData* data = UIImageJPEGRepresentation(value, 1);
            NSNumber* maxLength = MaxData;
            NSAssert(data.length<maxLength.integerValue,@"最大存储限制为100M");
            return [data base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
        }else{
            return [UIImage imageWithData:[[NSData alloc] initWithBase64EncodedString:value options:NSDataBase64DecodingIgnoreUnknownCharacters]];
        }
    }else if(([type hasPrefix:ekw_typeHead_UI]||[type hasPrefix:ekw_typeHead__UI])&&[type containsString:@"Color"]){
        if(encode){
            CGFloat r, g, b, a;
            [value getRed:&r green:&g blue:&b alpha:&a];
            return [NSString stringWithFormat:@"%.3f,%.3f,%.3f,%.3f", r, g, b, a];
        }else{
            NSArray<NSString*>* arr = [value componentsSeparatedByString:@","];
            return [UIColor colorWithRed:arr[0].floatValue green:arr[1].floatValue blue:arr[2].floatValue alpha:arr[3].floatValue];
        }
    }else if ([type containsString:@"NSRange"]){
        if(encode){
            return NSStringFromRange([value rangeValue]);
        }else{
            return [NSValue valueWithRange:NSRangeFromString(value)];
        }
    }else if ([type containsString:@"CGRect"]&&[type containsString:@"CGPoint"]&&[type containsString:@"CGSize"]){
        if(encode){
            return NSStringFromCGRect([value CGRectValue]);
        }else{
            return [NSValue valueWithCGRect:CGRectFromString(value)];
        }
    }else if (![type containsString:@"CGRect"]&&[type containsString:@"CGPoint"]&&![type containsString:@"CGSize"]){
        if(encode){
            return NSStringFromCGPoint([value CGPointValue]);
        }else{
            return [NSValue valueWithCGPoint:CGPointFromString(value)];
        }
    }else if (![type containsString:@"CGRect"]&&![type containsString:@"CGPoint"]&&[type containsString:@"CGSize"]){
        if(encode){
            return NSStringFromCGSize([value CGSizeValue]);
        }else{
            return [NSValue valueWithCGSize:CGSizeFromString(value)];
        }
    }else if([type isEqualToString:@"i"]||[type isEqualToString:@"I"]||
             [type isEqualToString:@"s"]||[type isEqualToString:@"S"]||
             [type isEqualToString:@"q"]||[type isEqualToString:@"Q"]||
             [type isEqualToString:@"b"]||[type isEqualToString:@"B"]||
             [type isEqualToString:@"c"]||[type isEqualToString:@"C"]||
             [type isEqualToString:@"l"]||[type isEqualToString:@"L"]){
        return value;
    }else if([type isEqualToString:@"f"]||[type isEqualToString:@"F"]||
             [type isEqualToString:@"d"]||[type isEqualToString:@"D"]){
        return value;
    }else{
        
        if(encode){
            NSBundle *bundle = [NSBundle bundleForClass:[value class]];
            if(bundle == [NSBundle mainBundle]){//自定义的类
                return [self jsonStringWithArray:@[value]];
            }else{//特殊类型
                return [self archivedDataWithRootObject:value];
            }
        }else{
            if([value containsString:EKWModel]){//自定义的类
                return [self arrayFromJsonString:value].firstObject;
            }else{//特殊类型
                return [self unarchivedObjectOfType:type fromValue:value];
            }
        }
    }
}

+ (nullable NSData *)archivedDataWithRootObject:(id)object {
    if (@available(iOS 12.0, *)) {
        return [NSKeyedArchiver archivedDataWithRootObject:object requiringSecureCoding:YES error:nil];
    } else {
        return [[NSKeyedArchiver archivedDataWithRootObject:object] base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
    }
}

+ (id)unarchivedObjectOfType:(NSString *)type
                   fromValue:(NSString *)value {
    NSData* data = [[NSData alloc] initWithBase64EncodedString:value options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (@available(iOS 12.0, *)) {
        return [NSKeyedUnarchiver unarchivedObjectOfClass:NSClassFromString(type) fromData:data error:nil];
    } else {
        return [NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
}

//json字符串转NSDictionary
+(NSDictionary*)dictionaryFromJsonString:(NSString*)jsonString{
    if(!jsonString || [jsonString isKindOfClass:[NSNull class]])return nil;
    
    if([jsonString containsString:EKWModel] || [jsonString containsString:EKWData]){
        NSMutableDictionary* dictM = [NSMutableDictionary dictionary];
        NSDictionary* dictSrc = [self jsonWithString:jsonString];
        for(NSString* keySrc in dictSrc.allKeys){
            NSDictionary* dictDest = dictSrc[keySrc];
            dictM[keySrc]= [self valueForDictionaryRead:dictDest];
        }
        return dictM;
    }else{
        return [self jsonWithString:jsonString];
    }
}

//根据NSDictionary转换从数据库读取回来的字典数据
+(id)valueForDictionaryRead:(NSDictionary*)dictDest{
    
    NSString* keyDest = dictDest.allKeys.firstObject;
    if([keyDest isEqualToString:EKWValue]){
        return dictDest[keyDest];
    }else if ([keyDest isEqualToString:EKWData]){
        return [[NSData alloc] initWithBase64EncodedString:dictDest[keyDest] options:NSDataBase64DecodingIgnoreUnknownCharacters];
    }else if([keyDest isEqualToString:EKWSet]){
        return [self arrayFromJsonString:dictDest[keyDest]];
    }else if([keyDest isEqualToString:EKWArray]){
        return [self arrayFromJsonString:dictDest[keyDest]];
    }else if([keyDest isEqualToString:EKWDictionary]){
        return [self dictionaryFromJsonString:dictDest[keyDest]];
    }else if([keyDest containsString:EKWModel]){
        NSString* claName = [keyDest componentsSeparatedByString:@"*"].lastObject;
        NSDictionary* valueDict = [self jsonWithString:dictDest[keyDest]];
        return [self objectFromJsonStringWithTableName:claName class:NSClassFromString(claName) valueDict:valueDict];
    }else{
        NSAssert(NO,@"没有找到匹配的解析类型");
        return nil;
    }
}

/**
 存储转换用的字典转化成对象处理函数.
 */
+(id)objectFromJsonStringWithTableName:(NSString* _Nonnull)tablename class:(__unsafe_unretained _Nonnull Class)cla valueDict:(NSDictionary*)valueDict{
    id object = [cla new];
    NSMutableArray* valueDictKeys = [NSMutableArray arrayWithArray:valueDict.allKeys];
    NSMutableArray* keyAndTypes = [NSMutableArray arrayWithArray:[self getClassIvarList:cla Object:nil onlyKey:NO]];
    [keyAndTypes removeObject:[NSString stringWithFormat:@"%@*q",ekw_primaryKey]];
    
    
    for(int i=0;i<valueDictKeys.count;i++){
        NSString* sqlKey = valueDictKeys[i];
        NSString* tempSqlKey = sqlKey;
        if([sqlKey containsString:PREFiX]){
            tempSqlKey = [sqlKey stringByReplacingOccurrencesOfString:PREFiX withString:@""];
        }
        for(NSString* keyAndType in keyAndTypes){
            NSArray* arrKT = [keyAndType componentsSeparatedByString:@"*"];
            NSString* key = [arrKT firstObject];
            
            NSString* type = [arrKT lastObject];
            
            if ([tempSqlKey isEqualToString:key]){
                id tempValue = valueDict[sqlKey];
                id ivarValue = [self getSqlValue:tempValue type:type encode:NO];
                !ivarValue?:[object setValue:ivarValue forKey:key];
                [keyAndTypes removeObject:keyAndType];
                [valueDictKeys removeObjectAtIndex:i];
                i--;
                break;//匹配处理完后跳出内循环.
            }
        }
    }

    return object;
}

//json字符串转NSArray
+(NSArray*)arrayFromJsonString:(NSString*)jsonString{
    if(!jsonString || [jsonString isKindOfClass:[NSNull class]])return nil;
    
    if([jsonString containsString:EKWModel] || [jsonString containsString:EKWData]){
        NSMutableArray* arrM = [NSMutableArray array];
        NSArray* array = [self jsonWithString:jsonString];
        for(NSDictionary* dict in array){
            [arrM addObject:[self valueForArrayRead:dict]];
        }
        return arrM;
    }else{
        return [self jsonWithString:jsonString];
    }
}

//根据NSDictionary转换从数据库读取回来的数组数据
+(id)valueForArrayRead:(NSDictionary*)dictionary{
    
    NSString* key = dictionary.allKeys.firstObject;
    if ([key isEqualToString:EKWValue]) {
        return dictionary[key];
    }else if ([key isEqualToString:EKWData]){
        return [[NSData alloc] initWithBase64EncodedString:dictionary[key] options:NSDataBase64DecodingIgnoreUnknownCharacters];
    }else if([key isEqualToString:EKWSet]){
        return [self arrayFromJsonString:dictionary[key]];
    }else if([key isEqualToString:EKWArray]){
        return [self arrayFromJsonString:dictionary[key]];
    }else if ([key isEqualToString:EKWDictionary]){
        return [self dictionaryFromJsonString:dictionary[key]];
    }else if ([key containsString:EKWModel]){
        NSString* claName = [key componentsSeparatedByString:@"*"].lastObject;
        NSDictionary* valueDict = [self jsonWithString:dictionary[key]];
        id object = [self objectFromJsonStringWithTableName:claName class:NSClassFromString(claName) valueDict:valueDict];
        return object;
    }else{
        NSAssert(NO,@"没有找到匹配的解析类型");
        return nil;
    }
    
}

//字典转json字符串.
+(NSString*)jsonStringWithDictionary:(NSDictionary*)dictionary{
    if ([NSJSONSerialization isValidJSONObject:dictionary]) {
        return [self dataToJson:dictionary];
    }else{
        NSMutableDictionary* dictM = [NSMutableDictionary dictionary];
        for(NSString* key in dictionary.allKeys){
            dictM[key] = [self dictionaryForDictionaryInsert:dictionary[key]];
        }
        return [self dataToJson:dictM];
    }
}

//根据value类型返回用于字典插入数据库的NSDictionary
+(NSDictionary*)dictionaryForDictionaryInsert:(id)value{
    if ([value isKindOfClass:[NSArray class]]){
        return @{EKWArray:[self jsonStringWithArray:value]};
    }else if ([value isKindOfClass:[NSSet class]]){
        return @{EKWSet:[self jsonStringWithArray:value]};
    }else if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]){
        return @{EKWValue:value};
    }else if([value isKindOfClass:[NSData class]]){
        NSData* data = value;
        NSNumber* maxLength = MaxData;
        NSAssert(data.length<maxLength.integerValue,@"最大存储限制为100M");
        return @{EKWData:[value base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]};
    }else if ([value isKindOfClass:[NSDictionary class]]){
        return @{EKWDictionary:[self jsonStringWithDictionary:value]};
    }else{
        NSString* modelKey = [NSString stringWithFormat:@"%@*%@",EKWModel,NSStringFromClass([value class])];
        return @{modelKey:[self jsonStringWithObject:value]};
    }
}

//NSArray,NSSet转json字符
+(NSString*)jsonStringWithArray:(id)array{
    if ([NSJSONSerialization isValidJSONObject:array]) {
        return [self dataToJson:array];
    }else{
        NSMutableArray* arrM = [NSMutableArray array];
        for(id value in array){
            [arrM addObject:[self dictionaryForArrayInsert:value]];
        }
        return [self dataToJson:arrM];
    }
}

//根据value类型返回用于数组插入数据库的NSDictionary
+(NSDictionary*)dictionaryForArrayInsert:(id)value{
    
    if ([value isKindOfClass:[NSArray class]]){
        return @{EKWArray:[self jsonStringWithArray:value]};
    }else if ([value isKindOfClass:[NSSet class]]){
        return @{EKWSet:[self jsonStringWithArray:value]};
    }else if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]){
        return @{EKWValue:value};
    }else if([value isKindOfClass:[NSData class]]){
        NSData* data = value;
        NSNumber* maxLength = MaxData;
        NSAssert(data.length<maxLength.integerValue,@"最大存储限制为100M");
        return @{EKWData:[value base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]};
    }else if ([value isKindOfClass:[NSDictionary class]]){
        return @{EKWDictionary:[self jsonStringWithDictionary:value]};
    }else{
        NSString* modelKey = [NSString stringWithFormat:@"%@*%@",EKWModel,NSStringFromClass([value class])];
        return @{modelKey:[self jsonStringWithObject:value]};
    }
    
}

//对象转json字符
+(NSString *)jsonStringWithObject:(id)object{
    NSMutableDictionary* keyValueDict = [NSMutableDictionary dictionary];
    NSArray* keyAndTypes = [EKWTool getClassIvarList:[object class] Object:object onlyKey:NO];
    //忽略属性
    NSArray* ignoreKeys = [EKWTool executeSelector:ekw_ignoreKeysSelector forClass:[object class]];
    for(NSString* keyAndType in keyAndTypes){
        NSArray* arr = [keyAndType componentsSeparatedByString:@"*"];
        NSString* propertyName = arr[0];
        NSString* propertyType = arr[1];
        
        if([ignoreKeys containsObject:propertyName])continue;
        
        if(![propertyName isEqualToString:ekw_primaryKey]){
            id propertyValue = [object valueForKey:propertyName];
            if (propertyValue){
                id Value = [self getSqlValue:propertyValue type:propertyType encode:YES];
                keyValueDict[propertyName] = Value;
            }
        }
    }
    return [self dataToJson:keyValueDict];
}

/**
 字典转json字符 .
 */
+(NSString*)dataToJson:(id)data{
    NSAssert(data,@"数据不能为空!");
    NSError *parseError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingPrettyPrinted error:&parseError];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

/**
 json字符转json格式数据 .
 */
+(id)jsonWithString:(NSString*)jsonString {
    NSAssert(jsonString,@"数据不能为空!");
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    id dic = [NSJSONSerialization JSONObjectWithData:jsonData
                                             options:NSJSONReadingMutableContainers
                                               error:&err];
    
    NSAssert(!err,@"json解析失败");
    return dic;
}

#pragma mark - Model的属性字段改变时 刷新数据库 调用的方法
/**
 根据类获取变量名列表
 @onlyKey YES:紧紧返回key,NO:在key后面添加type.
 */
+(NSArray *)getClassIvarList:(__unsafe_unretained Class)cla Object:(_Nullable id)object onlyKey:(BOOL)onlyKey {
    
    //获取缓存的属性信息
    NSCache *cache = [NSCache ekw_cache];
    NSString *cacheKey;
    cacheKey = onlyKey?[NSString stringWithFormat:@"%@_IvarList_yes",NSStringFromClass(cla)]:[NSString stringWithFormat:@"%@_IvarList_no",NSStringFromClass(cla)];
    NSArray *cachekeys = [cache objectForKey:cacheKey];
    if(cachekeys){
        return cachekeys;
    }
    
    NSMutableArray *keys = [NSMutableArray array];
    if(onlyKey){
        [keys addObject:ekw_primaryKey];
        //zx
    }else{
        //手动添加库自带的自动增长主键ID和类型q
        [keys addObject:[NSString stringWithFormat:@"%@*q",ekw_primaryKey]];
        //zx
    }
    
    [self ekw_enumerateClasses:cla complete:^(__unsafe_unretained Class c, BOOL *stop) {
        unsigned int numIvars; //成员变量个数
        Ivar *vars = class_copyIvarList(c, &numIvars);
        for(int i = 0; i < numIvars; i++) {
            Ivar thisIvar = vars[i];
            NSString *key = [NSString stringWithUTF8String:ivar_getName(thisIvar)];//获取成员变量的名
            if ([key hasPrefix:@"_"]) {
                key = [key substringFromIndex:1];
            }
            if (!onlyKey) {
                //获取成员变量的数据类型
                NSString *type = [NSString stringWithUTF8String:ivar_getTypeEncoding(thisIvar)];
                key = [NSString stringWithFormat:@"%@*%@",key,type];
            }
            [keys addObject:key];//存储对象的变量名
        }
        free(vars);//释放资源
    }];
    
    [cache setObject:keys forKey:cacheKey];
    
    return keys;
}

+ (void)ekw_enumerateClasses:(__unsafe_unretained Class)srcCla complete:(EKWClassesEnumeration)enumeration {
    // 1.没有block就直接返回
    if (enumeration == nil) return;
    // 2.停止遍历的标记
    BOOL stop = NO;
    // 3.当前正在遍历的类
    Class c = srcCla;
    // 4.开始遍历每一个类
    while (c && !stop) {
        // 4.1.执行操作
        enumeration(c, &stop);
        // 4.2.获得父类
        c = class_getSuperclass(c);
        if ([self isClassFromFoundation:c]) break;
    }
}

+ (BOOL)isClassFromFoundation:(Class)c {
    //zx
    if (c == [NSObject class]) return YES;
    __block BOOL result = NO;
    [[self foundationClasses] enumerateObjectsUsingBlock:^(Class foundationClass, BOOL *stop) {
        if ([c isSubclassOfClass:foundationClass]) {
            result = YES;
            *stop = YES;
        }
    }];
    return result;
}

+ (NSSet *)foundationClasses {
    if (foundationClasses_ == nil) {
        // 集合中没有NSObject，因为几乎所有的类都是继承自NSObject，具体是不是NSObject需要特殊判断
        foundationClasses_ = [NSSet setWithObjects:
                              [NSURL class],
//                              [NSDate class],
                              [NSValue class],
                              [NSData class],
                              [NSError class],
                              [NSArray class],
                              [NSDictionary class],
                              [NSString class],
                              [NSAttributedString class], nil];
    }
    return foundationClasses_;
}


#pragma mark - Base Tool Method
/**
 封装处理传入数据库的key和value.
 */
NSString *ekw_sqlKey(NSString *key) {
    return [NSString stringWithFormat:@"%@%@",PREFiX,key];
}

/**
 根据传入的对象获取表名.
 */
+(NSString *)getTableNameWithObject:(id)object {
//    NSString *tablename = [object valueForKey:ekw_tableNameKey];
//    if(tablename == nil) {
//        tablename = NSStringFromClass([object class]);
//    }
//    return tablename;
    //zx
    return NSStringFromClass([object class]);
}

/**
 判断并获取字段类型
 */
+(NSString*)keyAndType:(NSString*)param {
    NSArray *array = [param componentsSeparatedByString:@"*"];
    NSString *key = array[0];
    NSString *type = array[1];
    NSString *SqlType;
    type = [self getSqlType:type];
    if ([SqlText isEqualToString:type]) {
        SqlType = SqlText;
    }else if ([SqlReal isEqualToString:type]){
        SqlType = SqlReal;
    }else if ([SqlInteger isEqualToString:type]){
        SqlType = SqlInteger;
    }else{
        NSAssert(NO,@"没有找到匹配的类型!");
    }

    return [NSString stringWithFormat:@"%@ %@",[NSString stringWithFormat:@"%@%@",PREFiX, key], SqlType];
}

+(NSString*)getSqlType:(NSString*)type{
    if([type isEqualToString:@"i"]||[type isEqualToString:@"I"]||
       [type isEqualToString:@"s"]||[type isEqualToString:@"S"]||
       [type isEqualToString:@"q"]||[type isEqualToString:@"Q"]||
       [type isEqualToString:@"b"]||[type isEqualToString:@"B"]||
       [type isEqualToString:@"c"]||[type isEqualToString:@"C"]|
       [type isEqualToString:@"l"]||[type isEqualToString:@"L"]) {
        return SqlInteger;
    }else if([type isEqualToString:@"f"]||[type isEqualToString:@"F"]||
             [type isEqualToString:@"d"]||[type isEqualToString:@"D"]){
        return SqlReal;
    }else{
        return SqlText;
    }
}

/**
 判断是不是 "唯一约束" 字段.
 */
+(BOOL)isUniqueKey:(NSString*)uniqueKey with:(NSString*)param {
    NSArray *array = [param componentsSeparatedByString:@"*"];
    NSString *key = array[0];
    return [uniqueKey isEqualToString:key];
}

/**
 过滤建表的key ，//zx 后期可以优化，先拿 ignoredKeys （往往字段比较少）来遍历
 */
+(NSArray *)filtCreateKeys:(NSArray*)ekw_createkeys ignoredkeys:(NSArray*)ekw_ignoredkeys {
    NSMutableArray *createKeys = [NSMutableArray arrayWithArray:ekw_createkeys];
    NSMutableArray *ignoredKeys = [NSMutableArray arrayWithArray:ekw_ignoredkeys];
    //判断是否有需要忽略的key集合.
    if (ignoredKeys.count){
        for(__block int i=0;i<createKeys.count;i++){
            if(ignoredKeys.count){
                NSString *createKey = [createKeys[i] componentsSeparatedByString:@"*"][0];
                [ignoredKeys enumerateObjectsUsingBlock:^(id  _Nonnull ignoreKey, NSUInteger idx, BOOL  *_Nonnull stop) {
                    if([createKey isEqualToString:ignoreKey]){
                        [createKeys removeObjectAtIndex:i];
                        [ignoredKeys removeObjectAtIndex:idx];
                        i--;
                        *stop = YES;
                    }
                }];
            }else{
                break;
            }
        }
    }
    return createKeys;
}

/**
 判断类是否实现了某个类方法.
 */
+(id)executeSelector:(SEL)selector forClass:(Class)cla {
    id obj = nil;
    if ([cla respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        obj = [cla performSelector:selector];
#pragma clang diagnostic pop
    }
    return obj;
}

@end
