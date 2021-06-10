//
//  CipherGenerator.m
//  EKFMDB
//
//  Created by Apple on 2021/6/10.
//

#import "CipherGenerator.h"

@implementation CipherGenerator

+(NSString*)cipherEncrypt {
    return cipherEncrypt([confuseString(srcArray()) UTF8String],[confuseString(keyArray()) UTF8String]);
}

static NSString* cipherEncrypt(const char*src ,const char *key) {
    
    if (src == NULL || key == NULL) {
        return nil;
    }
    size_t keyLen = strlen(key);
    size_t srcLen = strlen(src);
    
    char *temp = (char*)malloc(srcLen+1);
    memset(temp, 0x00, srcLen+1);
    
    for(uint sIndex = 0 ; src[sIndex] != '\0' ; sIndex++) {
        
        uint kIndex = sIndex%keyLen;
        char sCh = src[sIndex];
        char kCh = key[kIndex];
        if (isdigit(src[sIndex])) {
            temp[sIndex] = (sCh + kCh)%10 + '0';
        }else if (islower(sCh)){
            temp[sIndex] = (sCh + kCh)%26 + 'a';
        }else if (isupper(sCh)){
            temp[sIndex] = (sCh + kCh)%26 + 'A';
        }else{
            temp[sIndex] = src[sIndex];
        }
    }
    NSString *encrypt = [NSString stringWithFormat:@"%s",temp];
    free(temp);
    return encrypt;
}

static NSString *confuseString(NSArray *array) {
    
    NSMutableString *mutableString = [[NSMutableString alloc] initWithCapacity:array.count];
    
    for (NSInteger iIndex = 0; iIndex < array.count; iIndex+=3) {
        [mutableString appendString:array[iIndex]];
    }
    for (NSInteger iIndex = 0; iIndex + 1 < array.count; iIndex+=3) {
        [mutableString appendString:array[iIndex + 1]];
    }
    for (NSInteger iIndex = 0; iIndex + 2 < array.count; iIndex+=3) {
        [mutableString appendString:array[iIndex + 2]];
    }
    
    return [NSString stringWithString:mutableString];
}

NSArray* srcArray() {
    
    return   @[@"K",
               @"V",
               @"l",
               @"2",
               @"7",
               @"X",
               @"e",
               @"O",
               @"7",
               @"G",
               @"6",
               @"v",
               @"n",
               @"w",
               @"f",
               @"w"];
}

NSArray* keyArray() {
    
    return   @[@"c",
               @"r",
               @"y",
               @"p",
               @"t",
               @"o",
               @"g",
               @"r",
               @"a",
               @"p"];
}

@end
