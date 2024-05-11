use std::{collections::HashMap, convert::TryFrom, string, time::Duration};
use crate::StorageProcessor;


#[derive(Debug)]
pub struct ProofDal<'a, 'c> {
    pub(crate) storage: &'a mut StorageProcessor<'c>,
}

impl ProofDal<'_, '_> {

    pub async fn insert_proof(
        &mut self,
        proof_name: String,
        proof : Vec<u8>,
        prover : String,
    ){
        sqlx::query!(
            r#"
            INSERT INTO
                proofs (proof_name, proof, created_at, prover)
            VALUES
                ($1, $2, NOW(), $3)
            ON CONFLICT (proof_name) DO NOTHING
            "#,
            proof_name,
            proof,
            prover,
        )
        .execute(self.storage.conn())
        .await
        .unwrap();
    }

    pub async fn get_proof(
        & mut self,
        proof_name:String,
    ) -> Vec<u8>{
        let rows = sqlx::query!(
            r#"
            SELECT
                proof
            FROM
                proofs
            WHERE
                proof_name like $1
            LIMIT
                1
            "#,
            proof_name,
        )
        .fetch_optional(self.storage.conn())
        .await.unwrap();

        let record: Vec<u8> = rows.unwrap().proof.unwrap();
        record
    }

    pub async fn del_proof(
        &mut self,
        proof_name:String,
    ){
        sqlx::query!(
            r#"
            DELETE FROM
                proofs
            WHERE
                proof_name like $1
            "#,
            proof_name,
        )
        .execute(self.storage.conn())
        .await
        .unwrap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ ConnectionPool};

    // #[tokio::test]
    // async fn put_get() {
    //     let pool = ConnectionPool::test_pool().await;
    //     let mut conn = pool.access_storage().await.unwrap();

    //     let proof = vec![9, 0, 8, 9, 0, 7];

    //     // let result = object_store
    //     //     .put_raw(Bucket::ProverJobs, "test-key.bin", expected.clone())
    //     //     .await;

       
    //     let proof_name = "test-key.bin".to_string();
    //     conn.proof_dal()
    //         .insert_proof(proof_name, proof, "lucy".to_string())
    //         .await;
        
    //     let ret = conn.proof_dal().get_proof(proof_name).await;
       
    // }
}