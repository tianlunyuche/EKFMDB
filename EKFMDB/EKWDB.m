//
//  EKWDB.m
//  EKWParent
//
//  Created by 赵庄鑫 on 2018/8/24.
//  Copyright © 2018年 ekwing. All rights reserved.
//

#import "EKWDB.h"
#import "EKWTool.h"
#import "NSCache+EKWCache.h"
#import "CipherGenerator.h"

/**
 默认数据库名称
 */
#define SQLITE_NAME @"EKWFMDB.db"
#define MaxQueryPageNum 50

#define CachePath(name) [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:name]

@interface EKWDB()
/**
 数据库队列
 */
@property (nonatomic, strong) FMDatabaseQueue *queue;
@property (nonatomic, strong) FMDatabase *db;
@property (nonatomic, assign) BOOL inTransaction;
@property (nonatomic, copy) NSString *dbPath;

@end

static EKWDB* EKWdb = nil;
@implementation EKWDB

/**
 获取单例函数.
 */
+(_Nonnull instancetype)shareManager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        EKWdb = [[EKWDB alloc]init];
        EKWdb.encryptionKey = [CipherGenerator cipherEncrypt];
    });
    return EKWdb;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        //创建信号量.
        self.semaphore = dispatch_semaphore_create(1);
        self.encryptionKey = [CipherGenerator cipherEncrypt];
    }
    return self;
}

- (void)dealloc {
    //烧毁数据.
    if (_semaphore) {
        _semaphore = 0x00;
    }
    [self closeDB];
    if (EKWdb) {
        EKWdb = nil;
    }
}

- (FMDatabaseQueue *)queue {
    if(_queue)return _queue;
    _queue = [FMDatabaseQueue databaseQueueWithPath:self.dbPath];
    return _queue;
}

- (NSString *)dbPath {
    //获得沙盒中的数据库文件名
    NSString* name;
    if(_sqliteName) {
        name = [NSString stringWithFormat:@"%@.db",_sqliteName];
    }else{
        name = SQLITE_NAME;
    }
    NSString *dbPath = CachePath(name);
    return  dbPath;
}

/**
 创建表(如果存在则不创建).
 */
- (void)createTableWithTableName:(NSString* _Nonnull)name keys:(NSArray<NSString*>* _Nonnull)keys unionPrimaryKeys:(NSArray* _Nullable)unionPrimaryKeys uniqueKeys:(NSArray* _Nullable)uniqueKeys complete:(ekw_complete_B)complete {
    NSAssert(name,@"表名不能为空!");
    NSAssert(keys,@"字段数组不能为空!");
    //创表
    __block BOOL result;
    [self executeDB:^(FMDatabase * _Nonnull db) {
        NSString *header = [NSString stringWithFormat:@"create table if not exists %@ (", name];
        NSMutableString *sql = [[NSMutableString alloc] init];
        [sql appendString:header];
        
        NSInteger uniqueKeyFlag = uniqueKeys.count;
        NSMutableArray *tempUniqueKeys = [NSMutableArray arrayWithArray:uniqueKeys];
        for (int i = 0; i < keys.count; i ++) {
            NSString *key = [keys[i] componentsSeparatedByString:@"*"][0];
            
            if (tempUniqueKeys.count && [tempUniqueKeys containsObject:key]) {
                for (NSString *uniqueKey in tempUniqueKeys) {
                    if ([EKWTool isUniqueKey:uniqueKey with:keys[i]]) {
                        [sql appendFormat:@"%@ unique", [EKWTool keyAndType:keys[i]]];
                        [tempUniqueKeys removeObject:uniqueKey];
                        uniqueKeyFlag--;
                        break;
                    }
                }
            }else {
                if ([key isEqualToString:ekw_primaryKey] && !unionPrimaryKeys.count){
                    [sql appendFormat:@"%@ primary key autoincrement",[EKWTool keyAndType:keys[i]]];
                }else{
                    [sql appendString:[EKWTool keyAndType:keys[i]]];
                }
            }
            
            if (i == (keys.count-1)) {
                if(unionPrimaryKeys.count){
                    [sql appendString:@",primary key ("];
                    [unionPrimaryKeys enumerateObjectsUsingBlock:^(id  _Nonnull unionKey, NSUInteger idx, BOOL * _Nonnull stop) {
                        if(idx == 0){
                            [sql appendString:ekw_sqlKey(unionKey)];
                        }else{
                            [sql appendFormat:@",%@",ekw_sqlKey(unionKey)];
                        }
                    }];
                    [sql appendString:@")"];
                }
                [sql appendString:@");"];
            }else{
                [sql appendString:@","];
            }
        }
        
        if(uniqueKeys.count){
            NSAssert(!uniqueKeyFlag,@"没有找到设置的'唯一约束',请检查模型类.m文件的ekw_uniqueKeys函数返回值是否正确!");
        }
        
        result = [db executeUpdate:sql];
    }];
    complete(result);
}

#pragma mark - 查询
/**
 查询对象.
 */
- (void)queryObjectWithTableName:(NSString* _Nonnull)tablename class:(__unsafe_unretained _Nonnull Class)cla where:(NSString* _Nullable)where complete:(ekw_complete_A)complete {
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [self queryObjectQueueWithTableName:tablename class:cla where:where complete:complete];
    }
    dispatch_semaphore_signal(self.semaphore);
}

- (void)queryObjectQueueWithTableName:(NSString* _Nonnull)tablename class:(__unsafe_unretained _Nonnull Class)cla where:(NSString* _Nullable)where complete:(ekw_complete_A)complete {
    //检查是否建立了跟对象相对应的数据表
    __weak typeof(self) BGSelf = self;
    [self isExistWithTableName:tablename complete:^(BOOL isExist) {
        __strong typeof(BGSelf) strongSelf = BGSelf;
        if (!isExist){//如果不存在就返回空
            ekw_completeBlock(nil);
        }else{
            [strongSelf queryWithTableName:tablename where:where complete:^(NSArray * _Nullable array) {
                NSArray* resultArray = [EKWTool tansformDataFromSqlDataWithTableName:tablename class:cla array:array];
                ekw_completeBlock(resultArray);
            }];
        }
    }];
}

/**
 直接传入条件sql语句查询
 */
- (void)queryWithTableName:(NSString* _Nonnull)name conditions:(NSString* _Nullable)conditions complete:(ekw_complete_A)complete {
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [self queryQueueWithTableName:name conditions:conditions complete:complete];
    }
    dispatch_semaphore_signal(self.semaphore);
}


#pragma mark - 删除
- (void)deleteWithTableName:(NSString* _Nonnull)name conditions:(NSString* _Nullable)conditions complete:(ekw_complete_B)complete {
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    [self deleteQueueWithTableName:name conditions:conditions complete:complete];
    dispatch_semaphore_signal(self.semaphore);
}

- (void)deleteQueueWithTableName:(NSString* _Nonnull)name conditions:(NSString* _Nullable)conditions complete:(ekw_complete_B)complete{
    NSAssert(name,@"表名不能为空!");
    __block BOOL result;
    [self executeDB:^(FMDatabase * _Nonnull db) {
        NSString* SQL = conditions?[NSString stringWithFormat:@"delete from %@ %@",name,conditions]:[NSString stringWithFormat:@"delete from %@",name];

        result = [db executeUpdate:SQL];
    }];
    ekw_completeBlock(result);
}

#pragma mark - 批量插入
/**
 批量插入或更新
 */
- (void)ekw_saveOrUpateArray:(NSArray* _Nonnull)array ignoredKeys:(NSArray* const _Nullable)ignoredKeys complete:(ekw_complete_B)complete {
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        //判断是否建表.
        [EKWTool ifNotExistWillCreateTableWithObject:array.firstObject ignoredKeys:ignoredKeys];
        //自动判断是否有字段改变,自动刷新数据库.
        [self ifIvarChangeForObject:array.firstObject ignoredKeys:ignoredKeys];
        //转换模型数据 ,带前缀的字典数组
        NSArray* dictArray = [self getArray:array ignoredKeys:ignoredKeys filtModelInfoType:ekw_ModelInfoNone];
        //获取自定义表名
        NSString* tableName = [EKWTool getTableNameWithObject:array.firstObject];
        [self ekw_saveOrUpdateWithTableName:tableName class:[array.firstObject class] DictArray:dictArray complete:complete];
    }
    dispatch_semaphore_signal(self.semaphore);
}

-(NSArray*)getArray:(NSArray*)array ignoredKeys:(NSArray* const _Nullable)ignoredKeys filtModelInfoType:(ekw_getModelInfoType)filtModelInfoType{
    NSMutableArray* dictArray = [NSMutableArray array];
    [array enumerateObjectsUsingBlock:^(id  _Nonnull object, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary* dict = [EKWTool getDictWithObject:object ignoredKeys:ignoredKeys filtModelInfoType:filtModelInfoType];
        [dictArray addObject:dict];
    }];
    return dictArray;
}

/**
 批量插入或更新.
 */
- (void)ekw_saveOrUpdateWithTableName:(NSString* _Nonnull)tablename class:(__unsafe_unretained _Nonnull Class)cla DictArray:(NSArray<NSDictionary*>* _Nonnull)dictArray complete:(ekw_complete_B)complete{
    __block BOOL result;
    [self executeDB:^(FMDatabase * _Nonnull db) {
        [db beginTransaction];
        __block NSInteger counter = 0;
        //带前缀的字典数组
        [dictArray enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull dict, NSUInteger idx, BOOL * _Nonnull stop) {
            @autoreleasepool {
                NSString* ekw_id = ekw_sqlKey(ekw_primaryKey);
                //获得"唯一约束"
                NSArray* uniqueKeys = [EKWTool executeSelector:ekw_uniqueKeysSelector forClass:cla];
                //获得"联合主键"
                NSArray* unionPrimaryKeys =[EKWTool executeSelector:ekw_unionPrimaryKeysSelector forClass:cla];
                NSMutableDictionary* tempDict = [[NSMutableDictionary alloc] initWithDictionary:dict];
                NSMutableString* where = [NSMutableString new];
                BOOL isSave = NO;//是否存储还是更新.
                if(uniqueKeys.count || unionPrimaryKeys.count){
                    NSArray* tempKeys;
                    NSString* orAnd;
                    
                    if(unionPrimaryKeys.count){
                        tempKeys = unionPrimaryKeys;
                        orAnd = @"and";
                    }else{
                        tempKeys = uniqueKeys;
                        orAnd = @"or";
                    }
                    
                    if(tempKeys.count == 1){
                        NSString* tempkey = ekw_sqlKey([tempKeys firstObject]);
                        id tempkeyVlaue = tempDict[tempkey];
                        [where appendFormat:@" where %@=%@",tempkey,ekw_sqlValue(tempkeyVlaue)];
                    }else{
                        [where appendString:@" where"];
                        [tempKeys enumerateObjectsUsingBlock:^(NSString*  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop){
                            NSString* tempkey = ekw_sqlKey(obj);
                            id tempkeyVlaue = tempDict[tempkey];
                            if(idx < (tempKeys.count-1)){
                                [where appendFormat:@" %@=%@ %@",tempkey,ekw_sqlValue(tempkeyVlaue),orAnd];
                            }else{
                                [where appendFormat:@" %@=%@",tempkey,ekw_sqlValue(tempkeyVlaue)];
                            }
                        }];
                    }
                    NSString* dataCountSql = [NSString stringWithFormat:@"select count(*) from %@%@",tablename,where];
                    __block NSInteger dataCount = 0;
                    [db executeStatements:dataCountSql withResultBlock:^int(NSDictionary *resultsDictionary) {
                        dataCount = [[resultsDictionary.allValues lastObject] integerValue];
                        return 0;
                    }];

                    if(dataCount){
                        //更新操作
                        [tempKeys enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                            [tempDict removeObjectForKey:ekw_sqlKey(obj)];
                        }];
                    }else{
                        //插入操作
                        isSave = YES;
                    }
                }else{
                    if([tempDict.allKeys containsObject:ekw_id]){
                        //更新操作
                        id primaryKeyVlaue = tempDict[ekw_id];
                        [where appendFormat:@" where %@=%@",ekw_id,ekw_sqlValue(primaryKeyVlaue)];
                    }else{
                        //插入操作
                        isSave = YES;
                    }
                }
                
                NSMutableString* SQL = [[NSMutableString alloc] init];
                NSMutableArray* arguments = [NSMutableArray array];
                if(isSave){//存储操作
                    NSInteger num = [self getKeyMaxForTable:tablename key:ekw_id db:db];
                    [tempDict setValue:@(num+1) forKey:ekw_id];
                    [SQL appendFormat:@"insert into %@(",tablename];
                    NSArray* keys = tempDict.allKeys;
                    NSArray* values = tempDict.allValues;
                    for(int i=0;i<keys.count;i++){
                        [SQL appendFormat:@"%@",keys[i]];
                        if(i == (keys.count-1)){
                            [SQL appendString:@") "];
                        }else{
                            [SQL appendString:@","];
                        }
                    }
                    [SQL appendString:@"values("];
                    for(int i=0;i<values.count;i++){
                        [SQL appendString:@"?"];
                        if(i == (keys.count-1)){
                            [SQL appendString:@");"];
                        }else{
                            [SQL appendString:@","];
                        }
                        [arguments addObject:values[i]];
                    }
                }else{//更新操作
                    if([tempDict.allKeys containsObject:ekw_id]){
                        [tempDict removeObjectForKey:ekw_id];//移除主键
                    }
                    //zx
                    [SQL appendFormat:@"update %@ set ",tablename];
                    [tempDict enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
                        [SQL appendFormat:@"%@=?,",key];
                        [arguments addObject:obj];
                    }];
                    SQL = [NSMutableString stringWithString:[SQL substringToIndex:SQL.length-1]];
                    if(where.length) {
                        [SQL appendString:where];
                    }
                }
                
                
                BOOL flag = [db executeUpdate:SQL withArgumentsInArray:arguments];
                if(flag){
                    counter++;
                }
            }
        }];
        
        if (dictArray.count == counter){
            result = YES;
            [db commit];
        }else{
            result = NO;
            [db rollback];
        }
        
    }];

    ekw_completeBlock(result);
}

/**
 转换OC对象成数据库数据.
 */
NSString* ekw_sqlValue(id value) {
    
    if([value isKindOfClass:[NSNumber class]]) {
        return value;
    }else if([value isKindOfClass:[NSString class]]){
        return [NSString stringWithFormat:@"'%@'",value];
    }else{
        NSString* type = [NSString stringWithFormat:@"@\"%@\"",NSStringFromClass([value class])];
        value = [EKWTool getSqlValue:value type:type encode:YES];
        if ([value isKindOfClass:[NSString class]]) {
            return [NSString stringWithFormat:@"'%@'",value];
        }else{
            return value;
        }
    }
}

#pragma mark - 保存
/**
 存储一个对象.
 */
- (void)saveObject:(id _Nonnull)object ignoredKeys:(NSArray* const _Nullable)ignoredKeys complete:(ekw_complete_B)complete {
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    @autoreleasepool {
        [EKWTool ifNotExistWillCreateTableWithObject:object ignoredKeys:ignoredKeys];
        [self insertWithObject:object ignoredKeys:ignoredKeys complete:complete];
    }
    dispatch_semaphore_signal(self.semaphore);
}

/**
 处理插入的字典数据并返回
 */
- (void)insertWithObject:(id)object ignoredKeys:(NSArray* const _Nullable)ignoredKeys complete:(ekw_complete_B)complete {
    NSDictionary *dictM = [EKWTool getDictWithObject:object ignoredKeys:ignoredKeys filtModelInfoType:ekw_ModelInfoInsert];
    //自动判断是否有字段改变，自动刷新数据库
    [self ifIvarChangeForObject:object ignoredKeys:ignoredKeys];
    
    NSString *tableName = [EKWTool getTableNameWithObject:object];
    [self insertIntoTableName:tableName Dict:dictM complete:complete];
}

#pragma mark -
/**
 判断类属性是否有改变,智能刷新.
 */
- (void)ifIvarChangeForObject:(id)object ignoredKeys:(NSArray*)ignoredkeys{
    //获取缓存的属性信息
    NSCache* cache = [NSCache ekw_cache];
    //zx
    NSString *tableName = NSStringFromClass([object class]);
    NSString* cacheKey = [NSString stringWithFormat:@"%@_IvarChangeState",tableName];
    id IvarChangeState = [cache objectForKey:cacheKey];
    if(IvarChangeState){
        return;
    }else{
        [cache setObject:@(YES) forKey:cacheKey];
    }
    
    @autoreleasepool {
        //获取表名
        NSString* tableName = [EKWTool getTableNameWithObject:object];
        NSMutableArray* newKeys = [NSMutableArray array];
        NSMutableArray* sqlKeys = [NSMutableArray array];
        [self executeDB:^(FMDatabase * _Nonnull db) {
            NSString* SQL = [NSString stringWithFormat:@"select sql from sqlite_master where tbl_name='%@' and type='table';",tableName];
            NSMutableArray* tempArrayM = [NSMutableArray array];
            //获取表格所有列名.
            [db executeStatements:SQL withResultBlock:^int(NSDictionary *resultsDictionary) {
                NSString* allName = [resultsDictionary.allValues lastObject];
                allName = [allName stringByReplacingOccurrencesOfString:@"\"" withString:@""];
                NSRange range1 = [allName rangeOfString:@"("];
                allName = [allName substringFromIndex:range1.location+1];
                NSRange range2 = [allName rangeOfString:@")"];
                allName = [allName substringToIndex:range2.location];
                NSArray* sqlNames = [allName componentsSeparatedByString:@","];
                
                for(NSString* sqlName in sqlNames){
                    NSString* columnName = [[sqlName componentsSeparatedByString:@" "] firstObject];
                    [tempArrayM addObject:columnName];
                }
                return 0;
            }];
            NSArray* columNames = tempArrayM.count?tempArrayM:nil;
            NSArray* keyAndtypes = [EKWTool getClassIvarList:[object class] Object:object onlyKey:NO];
            for(NSString* keyAndtype in keyAndtypes){
                NSString* key = [[keyAndtype componentsSeparatedByString:@"*"] firstObject];
                if(ignoredkeys && [ignoredkeys containsObject:key])continue;
                
                key = [NSString stringWithFormat:@"%@%@",PREFiX,key];
                if (![columNames containsObject:key]) {
                    [newKeys addObject:keyAndtype];
                }
            }
            
            NSMutableArray* keys = [NSMutableArray arrayWithArray:[EKWTool getClassIvarList:[object class] Object:nil onlyKey:YES]];
            if (ignoredkeys) {
                [keys removeObjectsInArray:ignoredkeys];
            }
            [columNames enumerateObjectsUsingBlock:^(NSString* _Nonnull columName, NSUInteger idx, BOOL * _Nonnull stop) {
                NSString* propertyName = [columName stringByReplacingOccurrencesOfString:PREFiX withString:@""];
                if(![keys containsObject:propertyName]){
                    [sqlKeys addObject:columName];
                }
            }];
            
        }];
        
        if((sqlKeys.count==0) && (newKeys.count>0)){
            //此处只是增加了新的列.
            for(NSString* key in newKeys){
                //添加新字段
                [self addTable:tableName key:key complete:^(BOOL isSuccess){}];
            }
        }else if(sqlKeys.count>0){
            //字段发生改变,减少或名称变化,实行刷新数据库.
            NSMutableArray* newTableKeys = [[NSMutableArray alloc] initWithArray:[EKWTool getClassIvarList:[object class] Object:nil onlyKey:NO]];
            NSMutableArray* tempIgnoreKeys = [[NSMutableArray alloc] initWithArray:ignoredkeys];
            for(int i=0;i<newTableKeys.count;i++){
                NSString* key = [[newTableKeys[i] componentsSeparatedByString:@"*"] firstObject];
                if([tempIgnoreKeys containsObject:key]) {
                    [newTableKeys removeObject:newTableKeys[i]];
                    [tempIgnoreKeys removeObject:key];
                    i--;
                }
                if(tempIgnoreKeys.count == 0){
                    break;
                }
            }
            [self refreshQueueTable:tableName class:[object class] keys:newTableKeys complete:nil];
        }else;
    }
}

- (void)refreshQueueTable:(NSString* _Nonnull)name class:(__unsafe_unretained _Nonnull Class)cla keys:(NSArray<NSString*>* const _Nonnull)keys complete:(ekw_complete_I)complete{
    NSAssert(name,@"表名不能为空!");
    NSAssert(keys,@"字段数组不能为空!");
    [self isExistWithTableName:name complete:^(BOOL isSuccess){
        if (!isSuccess){

            ekw_completeBlock(ekw_error);
            return;
        }
    }];
    NSString* wkeTempTable = @"wkeTempTable";
    //事务操作.
    __block int recordFailCount = 0;
    [self executeTransation:^BOOL{
        [self copyA:name toB:wkeTempTable class:cla keys:keys complete:^(ekw_dealState result) {
            if(result == ekw_complete){
                recordFailCount++;
            }
        }];
        [self dropTable:name complete:^(BOOL isSuccess) {
            if(isSuccess)recordFailCount++;
        }];
        [self copyA:wkeTempTable toB:name class:cla keys:keys complete:^(ekw_dealState result) {
            if(result == ekw_complete){
                recordFailCount++;
            }
        }];
        [self dropTable:wkeTempTable complete:^(BOOL isSuccess) {
            if(isSuccess)recordFailCount++;
        }];
        if(recordFailCount != 4){
           
        }
        return recordFailCount==4;
    }];
    
    //回调结果.
    if (recordFailCount==0) {
        ekw_completeBlock(ekw_error);
    }else if (recordFailCount>0&&recordFailCount<4){
        ekw_completeBlock(ekw_incomplete);
    }else{
        ekw_completeBlock(ekw_complete);
    }
}

- (void)copyA:(NSString* _Nonnull)A toB:(NSString* _Nonnull)B class:(__unsafe_unretained _Nonnull Class)cla keys:(NSArray<NSString*>* const _Nonnull)keys complete:(ekw_complete_I)complete{
    //获取"唯一约束"字段名
    NSArray* uniqueKeys = [EKWTool executeSelector:ekw_uniqueKeysSelector forClass:cla];
    //获取“联合主键”字段名
    NSArray* unionPrimaryKeys = [EKWTool executeSelector:ekw_unionPrimaryKeysSelector forClass:cla];
    //建立一张临时表
    __block BOOL createFlag;
    [self createTableWithTableName:B keys:keys unionPrimaryKeys:unionPrimaryKeys uniqueKeys:uniqueKeys complete:^(BOOL isSuccess) {
        createFlag = isSuccess;
    }];
    if (!createFlag){

        ekw_completeBlock(ekw_error);
        return;
    }
    __block ekw_dealState refreshstate = ekw_error;
    __block BOOL recordError = NO;
    __block BOOL recordSuccess = NO;
    __weak typeof(self) BGSelf = self;
    NSInteger count = [self countQueueForTable:A where:nil];
    //zx
    if (count == 0) {
        complete(ekw_complete);
        return;
    }
    for(NSInteger i=0;i<count;i+=MaxQueryPageNum){
        @autoreleasepool{//由于查询出来的数据量可能巨大,所以加入自动释放池.
            NSString* param = [NSString stringWithFormat:@"limit %@,%@",@(i),@(MaxQueryPageNum)];
            [self queryWithTableName:A where:param complete:^(NSArray * _Nullable array) {
                for(NSDictionary* oldDict in array){
                    NSMutableDictionary* newDict = [NSMutableDictionary dictionary];
                    for(NSString* keyAndType in keys){
                        NSString* key = [keyAndType componentsSeparatedByString:@"*"][0];
                        //字段名前加上 @"ekw_"
                        key = [NSString stringWithFormat:@"%@%@",PREFiX,key];
                        if (oldDict[key]){
                            newDict[key] = oldDict[key];
                        }
                    }
                    //将旧表的数据插入到新表
                    [BGSelf insertIntoTableName:B Dict:newDict complete:^(BOOL isSuccess){
                        if (isSuccess){
                            if (!recordSuccess) {
                                recordSuccess = YES;
                            }
                        }else{
                            if (!recordError) {
                                recordError = YES;
                            }
                        }
                        
                    }];
                }
            }];
        }
    }
    
    if (complete){
        if (recordError && recordSuccess) {
            refreshstate = ekw_incomplete;
        }else if(recordError && !recordSuccess){
            refreshstate = ekw_error;
        }else if (recordSuccess && !recordError){
            refreshstate = ekw_complete;
        }else;
        complete(refreshstate);
    }
    
}


#pragma mark - 操作FMDB的方法层
/**
 插入数据.
 */
- (void)insertIntoTableName:(NSString* _Nonnull)name Dict:(NSDictionary* _Nonnull)dict complete:(ekw_complete_B)complete {
    NSAssert(name,@"表名不能为空!");
    NSAssert(dict,@"插入值字典不能为空!");
    __block BOOL result;
    
    [self executeDB:^(FMDatabase * _Nonnull db) {
        NSArray* keys = dict.allKeys;
        if([keys containsObject:ekw_sqlKey(ekw_primaryKey)]){
            NSInteger num = [self getKeyMaxForTable:name key:ekw_sqlKey(ekw_primaryKey) db:db];
            [dict setValue:@(num+1) forKey:ekw_sqlKey(ekw_primaryKey)];
        }
        NSArray* values = dict.allValues;
        NSMutableString* SQL = [[NSMutableString alloc] init];
        [SQL appendFormat:@"insert into %@(",name];
        for(int i=0;i<keys.count;i++){
            [SQL appendFormat:@"%@",keys[i]];
            if(i == (keys.count-1)){
                [SQL appendString:@") "];
            }else{
                [SQL appendString:@","];
            }
        }
        [SQL appendString:@"values("];
        for(int i=0;i<values.count;i++){
            [SQL appendString:@"?"];
            if(i == (keys.count-1)){
                [SQL appendString:@");"];
            }else{
                [SQL appendString:@","];
            }
        }
        
        result = [db executeUpdate:SQL withArgumentsInArray:values];
    }];
    //zx
    ekw_completeBlock(result);
}

-(NSInteger)getKeyMaxForTable:(NSString*)name key:(NSString*)key db:(FMDatabase*)db{
    __block NSInteger num = 0;
    [db executeStatements:[NSString stringWithFormat:@"select max(%@) from %@",key,name] withResultBlock:^int(NSDictionary *resultsDictionary){
        id dbResult = [resultsDictionary.allValues lastObject];
        if(dbResult && ![dbResult isKindOfClass:[NSNull class]]) {
            num = [dbResult integerValue];
        }
        return 0;
    }];
    return num;
}

/**
 数据库中是否存在表.
 */
- (void)isExistWithTableName:(NSString* _Nonnull)name complete:(ekw_complete_B)complete {
    NSAssert(name, @"表名不能为空！");
    __block BOOL result;
    [self executeDB:^(FMDatabase * _Nonnull db) {
        result = [db tableExists:name];
    }];
    ekw_completeBlock(result);
}

/*
 执行事务操作
 */
- (void)executeTransation:(BOOL (^_Nonnull)(void))block{
    [self executeDB:^(FMDatabase * _Nonnull db) {
        self.inTransaction = db.inTransaction;
        if (!self.inTransaction) {
            self.inTransaction = [db beginTransaction];
        }
        BOOL isCommit = NO;
        isCommit = block();
        if (self.inTransaction){
            if (isCommit) {
                [db commit];
            }else {
                [db rollback];
            }
            self.inTransaction = NO;
        }
    }];
}

/**
 查询该表中有多少条数据
 */
-(NSInteger)countQueueForTable:(NSString* _Nonnull)name where:(NSArray* _Nullable)where{
    NSAssert(name,@"表名不能为空!");
    NSAssert(!(where.count%3),@"条件数组错误!");
    NSMutableString* strM = [NSMutableString string];
    !where?:[strM appendString:@" where "];
    for(int i=0;i<where.count;i+=3){
        if ([where[i+2] isKindOfClass:[NSString class]]) {
            [strM appendFormat:@"%@%@%@'%@'",PREFiX,where[i],where[i+1],where[i+2]];
        }else{
            [strM appendFormat:@"%@%@%@%@",PREFiX,where[i],where[i+1],where[i+2]];
        }
        
        if (i != (where.count-3)) {
            [strM appendString:@" and "];
        }
    }
    __block NSUInteger count=0;
    [self executeDB:^(FMDatabase * _Nonnull db) {
        NSString* SQL = [NSString stringWithFormat:@"select count(*) from %@%@",name,strM];

        [db executeStatements:SQL withResultBlock:^int(NSDictionary *resultsDictionary) {
            count = [[resultsDictionary.allValues lastObject] integerValue];
            return 0;
        }];
    }];
    return count;
}

//----------

/**
 动态添加表字段.
 */
- (void)addTable:(NSString* _Nonnull)name key:(NSString* _Nonnull)key complete:(ekw_complete_B)complete{
    NSAssert(name,@"表名不能为空!");
    __block BOOL result;
    [self executeDB:^(FMDatabase * _Nonnull db) {
        NSString* SQL = [NSString stringWithFormat:@"alter table %@ add %@;",name,[EKWTool keyAndType:key]];

        result = [db executeUpdate:SQL];
    }];
    ekw_completeBlock(result);
}

/**
 删除表.
 */
- (void)dropTable:(NSString* _Nonnull)name complete:(ekw_complete_B)complete{
    NSAssert(name,@"表名不能为空!");
    __block BOOL result;
    [self executeDB:^(FMDatabase * _Nonnull db) {
        NSString* SQL = [NSString stringWithFormat:@"drop table %@",name];

        result = [db executeUpdate:SQL];
    }];
    
    //zx
    ekw_completeBlock(result);
}

/**
 查询对象.
 */
- (void)queryWithTableName:(NSString* _Nonnull)name where:(NSString* _Nullable)where complete:(ekw_complete_A)complete{
    NSAssert(name,@"表名不能为空!");
    NSMutableArray* arrM = [[NSMutableArray alloc] init];
    [self executeDB:^(FMDatabase * _Nonnull db) {
        NSMutableString* SQL = [NSMutableString string];
        [SQL appendFormat:@"select * from %@",name];
        !where?:[SQL appendFormat:@" %@",where];

        // 1.查询数据
        FMResultSet *rs = [db executeQuery:SQL];
        if (rs == nil) {
            NSLog(@"查询错误,'表格'不存在!,请存储后再读取!");
        }
        // 2.遍历结果集
        while (rs.next) {
            NSMutableDictionary* dictM = [[NSMutableDictionary alloc] init];
            for (int i=0;i<[[[rs columnNameToIndexMap] allKeys] count];i++) {
                dictM[[rs columnNameForIndex:i]] = [rs objectForColumnIndex:i];
            }
            [arrM addObject:dictM];
        }
        //查询完后要关闭rs，不然会报@"Warning: there is at least one open result set around after performing
        [rs close];
    }];
    
    ekw_completeBlock(arrM);
}

- (void)queryQueueWithTableName:(NSString* _Nonnull)name conditions:(NSString* _Nullable)conditions complete:(ekw_complete_A)complete {
    NSAssert(name,@"表名不能为空!");
    __block NSMutableArray* arrM = nil;
    [self executeDB:^(FMDatabase * _Nonnull db){
        NSString* SQL = conditions?[NSString stringWithFormat:@"select * from %@ %@",name,conditions]:[NSString stringWithFormat:@"select * from %@",name];

        // 1.查询数据
        FMResultSet *rs = [db executeQuery:SQL];
        if (rs == nil) {
            NSLog(@"查询错误,可能是'类变量名'发生了改变或'字段','表格'不存在!,请存储后再读取!");
        }else{
            arrM = [[NSMutableArray alloc] init];
        }
        // 2.遍历结果集
        while (rs.next) {
            NSMutableDictionary* dictM = [[NSMutableDictionary alloc] init];
            for (int i=0;i<[[[rs columnNameToIndexMap] allKeys] count];i++) {
                dictM[[rs columnNameForIndex:i]] = [rs objectForColumnIndex:i];
            }
            [arrM addObject:dictM];
        }
        //查询完后要关闭rs，不然会报@"Warning: there is at least one open result set around after performing
        [rs close];
    }];
    
    ekw_completeBlock(arrM);
}

/**
 为了对象层的事物操作而封装的函数.
 */
- (void)executeDB:(void (^_Nonnull)(FMDatabase *_Nonnull db))block {
    NSAssert(block, @"block 是空的！");
    
    if (_db) { //为了事务操作防止死锁而设置.
        block(_db);
        return;
    } else {
        if (_queue == nil) {
            self.queue = [FMDatabaseQueue databaseQueueWithPath:self.dbPath];
            [_queue inDatabase:^(FMDatabase *db) {
#ifdef DEBUG
                    // debug模式下打印错误日志
                    db.logsErrors = YES;
#endif
                if (_encryptionKey.length > 0) {
                    [db setKey:_encryptionKey];
                }
            }];
        }
    }
    __weak typeof(self) weakSelf = self;
    [self.queue inDatabase:^(FMDatabase * _Nonnull db) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.db = db;
        block(db);
        strongSelf.db = nil;
    }];
}

/**
 关闭数据库.
 */
- (void)closeDB {
    if (_disableCloseDB) return;
    
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    if (!_inTransaction && _queue) {  //保证没有事务的情况下 关闭 数据库
        [_queue close]; //关闭数据库
        _queue = nil;
    }
    dispatch_semaphore_signal(self.semaphore);
}

@end
