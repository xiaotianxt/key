use anyhow::{bail, Result};
use security_framework::base::Error;
use security_framework::passwords::{
    delete_generic_password, generic_password, set_generic_password, PasswordOptions,
};
use security_framework_sys::base::errSecItemNotFound;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    service: String,
    account: String,
}

impl Target {
    pub fn new(service: String, account: String) -> Result<Self> {
        if service.is_empty() {
            bail!("service must not be empty");
        }
        if account.is_empty() {
            bail!("account must not be empty");
        }
        Ok(Self { service, account })
    }

    pub fn display(&self) -> String {
        format!("{}/{}", self.service, self.account)
    }
}

#[derive(Debug, Default)]
pub struct Keychain;

impl Keychain {
    pub fn new() -> Self {
        Self
    }

    pub fn set(&self, target: &Target, secret: &[u8]) -> Result<()> {
        set_generic_password(&target.service, &target.account, secret).map_err(Into::into)
    }

    pub fn get(&self, target: &Target) -> Result<Vec<u8>> {
        let options = PasswordOptions::new_generic_password(&target.service, &target.account);
        generic_password(options).map_err(Into::into)
    }

    pub fn delete(&self, target: &Target) -> Result<()> {
        delete_generic_password(&target.service, &target.account).map_err(Into::into)
    }

    pub fn exists(&self, target: &Target) -> Result<bool> {
        match self.get(target) {
            Ok(_) => Ok(true),
            Err(error) => {
                if let Some(keychain_error) = error.downcast_ref::<Error>() {
                    if keychain_error.code() == errSecItemNotFound {
                        return Ok(false);
                    }
                }
                Err(error)
            }
        }
    }
}
