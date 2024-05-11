use std::fmt::Debug;

use anyhow::{Context, Ok};
use async_trait::async_trait;
use zksync_dal::ConnectionPool;

use crate::raw::{Bucket, ObjectStore, ObjectStoreError};

impl From<anyhow::Error> for ObjectStoreError {
    fn from(err: anyhow::Error) -> Self {
        println!("pg operate err:{}", err);
        ObjectStoreError::Other(err.into())
    }
}

#[derive(Debug)]
pub(crate) struct PGObjectStore {
    connection_pool: ConnectionPool,
}

impl PGObjectStore {
    pub async fn new(postgres_base_url: String) -> Self {
        const MAX_POOL_SIZE_FOR_PROVER: u32 = 2;

        let connection_pool = ConnectionPool::builder(&postgres_base_url, MAX_POOL_SIZE_FOR_PROVER)
            .build();
            .await
            .context("PGObjectStore failed to build a connection pool")
            .unwrap();

        PGObjectStore { connection_pool }
    }

    fn filename(&self, bucket: Bucket, key: &str) -> String {
        format!("{bucket}_{key}")
    }
}

#[async_trait]
impl ObjectStore for PGObjectStore {
    async fn get_raw(&self, bucket: Bucket, key: &str) -> Result<Vec<u8>, ObjectStoreError> {
        let filename = self.filename(bucket, key);
        println!("get bucket:{}, key:{}, finename:{}", bucket, key, filename);

        let mut storage_processor = self.connection_pool.access_storage().await.unwrap();

        let mut transaction = storage_processor.start_transaction().await.unwrap();

        let ret = transaction.proof_dal().get_proof(filename).await;

        transaction.commit().await.unwrap();
        Ok(ret).map_err(|e| ObjectStoreError::from(e))
    }

    async fn put_raw(
        &self,
        bucket: Bucket,
        key: &str,
        value: Vec<u8>,
    ) -> Result<(), ObjectStoreError> {
        let filename = self.filename(bucket, key);
        println!("put bucket:{}, key:{}, finename:{}", bucket, key, filename);

        let mut storage_processor = self.connection_pool.access_storage().await.unwrap();

        let mut transaction = storage_processor.start_transaction().await.unwrap();

        transaction
            .proof_dal()
            .insert_proof(filename, value, "lucy".to_string())
            .await;

        transaction.commit().await.unwrap();
        Ok(()).map_err(|e| ObjectStoreError::from(e))
    }

    async fn remove_raw(&self, bucket: Bucket, key: &str) -> Result<(), ObjectStoreError> {
        let filename = self.filename(bucket, key);

        let mut storage_processor = self.connection_pool.access_storage().await.unwrap();
        let mut transaction = storage_processor.start_transaction().await.unwrap();

        transaction.proof_dal().del_proof(filename).await;

        transaction.commit().await.unwrap();
        Ok(()).map_err(|e| ObjectStoreError::from(e))
    }

    fn storage_prefix_raw(&self, bucket: Bucket) -> String {
        format!("{}", bucket)
    }
}

#[cfg(test)]
mod test {

    // use super::*;
    // #[tokio::test]
    // async fn test_put() {
    //     let gp_url = "postgres://postgres:notsecurepassword@10.126.128.30/prover_local".to_string();

    //     let object_store = PGObjectStore::new(gp_url).await;
    //     let expected = vec![9, 0, 8, 9, 0, 7];

    //     let result = object_store
    //         .put_raw(Bucket::ProverJobs, "test-key.bin", expected.clone())
    //         .await;
    //     assert!(result.is_ok(), "result must be OK");
    //     let bytes = object_store
    //         .get_raw(Bucket::ProverJobs, "test-key.bin")
    //         .await
    //         .unwrap();
    //     assert_eq!(expected, bytes, "expected didn't match");
    // }

    // #[tokio::test]
    // async fn test_put() {
    //     let dir = TempDir::new("test-data").unwrap();
    //     let path = dir.into_path().into_os_string().into_string().unwrap();
    //     let object_store = FileBackedObjectStore::new(path).await;
    //     let bytes = vec![9, 0, 8, 9, 0, 7];
    //     let result = object_store
    //         .put_raw(Bucket::ProverJobs, "test-key.bin", bytes)
    //         .await;
    //     assert!(result.is_ok(), "result must be OK");
    // }

    // #[tokio::test]
    // async fn test_remove() {
    //     let dir = TempDir::new("test-data").unwrap();
    //     let path = dir.into_path().into_os_string().into_string().unwrap();
    //     let object_store = FileBackedObjectStore::new(path).await;
    //     let result = object_store
    //         .put_raw(Bucket::ProverJobs, "test-key.bin", vec![0, 1])
    //         .await;
    //     assert!(result.is_ok(), "result must be OK");
    //     let result = object_store
    //         .remove_raw(Bucket::ProverJobs, "test-key.bin")
    //         .await;
    //     assert!(result.is_ok(), "result must be OK");
    // }
}
