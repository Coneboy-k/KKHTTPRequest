//
//  KKBaseHttpQueue.h
//  Operation
//
//  Created by SunKe on 14/10/22.
//  Copyright (c) 2014年 Coneboy_k. All rights reserved.
//

#import <Foundation/Foundation.h>

@class KKHttpOperation;

@interface KKBaseHttpQueue : NSObject

+ (instancetype)sharedRequestQueue;


// 添加队列
- (void)enqueueOperation:(KKHttpOperation *)operation;

/**
 *  结束所有的请求
 */
-(void)cancelAllOperations;

/**
 *  取消指定的队列
 *
 *  @param operation 取消的指定队列
 */
- (void)cancelSpecifiedOperation:(KKHttpOperation *)operation;

@end
