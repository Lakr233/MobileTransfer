// Native, ephemeral AppleMediaServices authentication. Credentials use private stdin/stdout pipes.
#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
@interface NSObject (ITMSystemAuthentication)
- (id)initWithDSID:(id)dsid altDSID:(id)altDSID username:(id)username options:(id)options;
- (id)initWithRequest:(id)request;
- (id)performAuthentication;
- (id)resultWithTimeout:(double)timeout error:(NSError **)error;
- (id)account;
- (id)username;
- (id)ams_DSID;
- (id)ams_storefront;
- (id)ams_password;
- (id)ams_firstName;
- (id)ams_lastName;
@end
static void finish(NSDictionary *value){
 NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
 if(data){fwrite(data.bytes,1,data.length,stdout);fwrite("\n",1,1,stdout);fflush(stdout);}
 exit(0);
}
static NSString *text(id value){return [value isKindOfClass:NSString.class]?value:([value isKindOfClass:NSNumber.class]?[value stringValue]:@"");}
int main(int argc,const char **argv){@autoreleasepool{
 if(!dlopen("/System/Library/PrivateFrameworks/AppleMediaServices.framework/AppleMediaServices",RTLD_LAZY)){finish(@{@"status":@"failed",@"phase":@"system-framework"});}
 @try {
 id options=[[NSClassFromString(@"AMSAuthenticateOptions") alloc]init];
 if(!options||![options respondsToSelector:NSSelectorFromString(@"setEphemeral:")]){finish(@{@"status":@"failed",@"phase":@"system-options"});}
 [options setValue:@YES forKey:@"ephemeral"];
 [options setValue:@NO forKey:@"canMakeAccountActive"];
 [options setValue:@0 forKey:@"accountSaveOptions"];
 [options setValue:@NO forKey:@"enableAccountCreation"];
 [options setValue:@NO forKey:@"allowSecondaryCredentialSource"];
 if(![[options valueForKey:@"ephemeral"]boolValue]||[[options valueForKey:@"canMakeAccountActive"]boolValue]||[[options valueForKey:@"accountSaveOptions"]integerValue]!=0){finish(@{@"status":@"failed",@"phase":@"system-options"});}
 if(argc>1&&strcmp(argv[1],"--preflight")==0){finish(@{@"status":@"ready",@"phase":@"system-ephemeral-options"});}
 NSMutableData *input=[NSMutableData data];uint8_t buffer[4096];size_t n;
 while((n=fread(buffer,1,sizeof(buffer),stdin))>0){[input appendBytes:buffer length:n];if(input.length>65536){finish(@{@"status":@"failed",@"phase":@"input"});}}
 NSDictionary *request=[NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
 NSString *email=text(request[@"email"]),*password=text(request[@"password"]);
 if(!email.length||!password.length){finish(@{@"status":@"failed",@"phase":@"input"});}
 [options setValue:password forKey:@"password"];
 [options setValue:@(argc<2 || strcmp(argv[1],"--no-dialog")!=0) forKey:@"allowServerDialogs"];
 [options setValue:@"iTM" forKey:@"proxyAppName"];
 [options setValue:@"tech.nootag.itm" forKey:@"proxyAppBundleID"];
 [options setValue:@"登录 Apple 账号以下载已拥有的 App 安装包" forKey:@"reason"];
 id authRequest=[[NSClassFromString(@"AMSAuthenticateRequest") alloc]initWithDSID:nil altDSID:nil username:email options:options];
 id task=[[NSClassFromString(@"AMSAuthenticateTask") alloc]initWithRequest:authRequest];
 if(!task||![task respondsToSelector:@selector(performAuthentication)]){finish(@{@"status":@"failed",@"phase":@"system-request"});}
 [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
 id promise=[task performAuthentication];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
  @try{
   NSError *error=nil;id result=[promise resultWithTimeout:110 error:&error];
   if(!result||error){
    // Return only domain/code, never NSError descriptions, headers or account data.
    NSMutableArray *chain=[NSMutableArray array];NSMutableArray *pending=[NSMutableArray array];
    if(error)[pending addObject:error];
    for(int i=0;i<24&&pending.count;i++){
        NSError *current=pending.firstObject;[pending removeObjectAtIndex:0];
        NSString *d=current.domain?:@"unknown";
        if([d hasPrefix:@"AM"]||[d hasPrefix:@"AK"]||[d hasPrefix:@"NS"]||[d hasPrefix:@"AC"]||[d hasPrefix:@"OS"]){NSString *entry=[NSString stringWithFormat:@"%@:%ld",d,(long)current.code];if(![chain containsObject:entry])[chain addObject:entry];}
        if([current.domain isEqualToString:NSCocoaErrorDomain]&&current.code==4099){
            NSString *detail=text(current.userInfo[NSDebugDescriptionErrorKey]);
            NSString *category=[detail.lowercaseString containsString:@"sandbox"]?@"sandbox-restricted":([detail.lowercaseString containsString:@"entitlement"]?@"entitlement-required":([detail.lowercaseString containsString:@"no such"]?@"service-not-found":@"connection-invalid"));
            [chain addObject:[@"XPC:" stringByAppendingString:category]];
            NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"com\\.apple\\.[A-Za-z0-9_.-]+" options:0 error:nil];
            for(NSTextCheckingResult *match in [regex matchesInString:detail options:0 range:NSMakeRange(0,detail.length)]){[chain addObject:[detail substringWithRange:match.range]];}
        }
        id underlying=current.userInfo[NSUnderlyingErrorKey];if([underlying isKindOfClass:NSError.class])[pending addObject:underlying];
        id multiple=current.userInfo[@"NSMultipleUnderlyingErrorsKey"];if([multiple isKindOfClass:NSArray.class])for(id child in multiple)if([child isKindOfClass:NSError.class])[pending addObject:child];
    }
    NSString *domain=chain.count?[chain componentsJoinedByString:@" → "]:@"unknown";
    if(![domain hasPrefix:@"AM"]&&![domain hasPrefix:@"AK"]&&![domain hasPrefix:@"NS"]&&![domain hasPrefix:@"AC"]){domain=@"system-authentication";}
    if(argc>1&&strcmp(argv[1],"--no-dialog")==0&&[email hasSuffix:@"@example.invalid"]){
        NSString *diagnostic=[@[error.localizedDescription?:@"",text(error.userInfo[NSLocalizedFailureReasonErrorKey])] componentsJoinedByString:@"; "];
        diagnostic=[[diagnostic stringByReplacingOccurrencesOfString:email withString:@"[synthetic-account]"]stringByReplacingOccurrencesOfString:password withString:@"[redacted]"];
        finish(@{@"status":@"failed",@"phase":@"system-authentication",@"failureType":[NSString stringWithFormat:@"%ld",(long)error.code],@"errorDomain":domain,@"syntheticDiagnostic":diagnostic});
    }
    finish(@{@"status":@"failed",@"phase":@"system-authentication",@"failureType":[NSString stringWithFormat:@"%ld",(long)error.code],@"errorDomain":domain});
   }
   id account=[result account];
   NSString *returnedUsername=text([account username]);
   if(!returnedUsername.length||[returnedUsername caseInsensitiveCompare:email]!=NSOrderedSame){finish(@{@"status":@"failed",@"phase":@"system-account-mismatch"});}
   NSString *token=text([account ams_password]);NSString *dsid=text([account ams_DSID]);NSString *store=[[text([account ams_storefront]) componentsSeparatedByString:@"-"]firstObject];
   if(!token.length||!dsid.length||!store.length){finish(@{@"status":@"failed",@"phase":@"system-store-credentials"});}
   NSDictionary *mapped=@{@"email":email,@"password":@"",@"appleId":email,@"store":store,@"firstName":text([account ams_firstName]),@"lastName":text([account ams_lastName]),@"passwordToken":token,@"directoryServicesIdentifier":dsid,@"cookie":@[]};
   finish(@{@"status":@"authenticated",@"phase":@"system-store-authenticated",@"account":mapped});
  }@catch(NSException *exception){finish(@{@"status":@"failed",@"phase":@"system-result"});}
 }});
 [NSApp run];
 }@catch(NSException *exception){finish(@{@"status":@"failed",@"phase":@"system-component"});}
 }return 0;}
