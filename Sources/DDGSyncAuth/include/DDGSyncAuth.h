#import "sodium/crypto_pwhash.h"
#import "sodium/crypto_box.h"
#import "sodium/crypto_secretbox.h"

#ifndef DDGSyncAuth_h
#define DDGSyncAuth_h

typedef enum : int {
    DDGSYNCAUTH_HASH_SIZE = 32,
    DDGSYNCAUTH_PRIMARY_KEY_SIZE = 32,
    DDGSYNCAUTH_SECRET_KEY_SIZE = 32,
    DDGSYNCAUTH_STRETCHED_PRIMARY_KEY_SIZE = 32,
    DDGSYNCAUTH_PROTECTED_SYMMETRIC_KEY_SIZE = (crypto_secretbox_MACBYTES + DDGSYNCAUTH_STRETCHED_PRIMARY_KEY_SIZE + crypto_secretbox_NONCEBYTES),
} DDGSyncAuthSizes;

typedef enum : int {
    DDGSYNCAUTH_OK,
    DDGSYNCAUTH_UNKNOWN_ERROR,
    DDGSYNCAUTH_INVALID_USERID,
    DDGSYNCAUTH_INVALID_PASSWORD,
    DDGSYNCAUTH_CREATE_PRIMARY_KEY_FAILED,
    DDGSYNCAUTH_CREATE_PASSWORD_HASH_FAILED,
    DDGSYNCAUTH_CREATE_STRETCHED_PRIMARY_KEY_FAILED,
    DDGSYNCAUTH_CREATE_PROTECTED_SECRET_KEY_FAILED,
} DDGSyncAuthResult;

/**
 * Used to create data needed to create an account.  Once the server returns a JWT, then store primary and secret key.
 *
 * @param primaryKey OUT - store this.  In combination with user id, this is the recovery key.
 * @param secretKey OUT - store this. This is used to encrypt an decrypt e2e data.
 * @param protectedSymmetricKey OUT - do not store this.  Send to /sign up endpoint.
 * @param passwordHash OUT - do not store this.  Send to /signup endpoint.
 * @param userId IN
 * @param password IN
 */
extern DDGSyncAuthResult ddgSyncGenerateAccountKeys(
    unsigned char primaryKey[DDGSYNCAUTH_PRIMARY_KEY_SIZE],
    unsigned char secretKey[DDGSYNCAUTH_SECRET_KEY_SIZE],
    unsigned char protectedSymmetricKey[DDGSYNCAUTH_PROTECTED_SYMMETRIC_KEY_SIZE],
    unsigned char passwordHash[DDGSYNCAUTH_HASH_SIZE],
    const char *userId,
    const char *password
);

#endif /* DDGSyncAuth_h */