use anchor_lang::prelude::*;
use anchor_lang::system_program;
use anchor_spl::{
    associated_token::AssociatedToken,
    metadata::{
        mpl_token_metadata::{
            accounts::{MasterEdition, Metadata as MetadataAccount},
            instructions::PrintV1CpiBuilder,
        },
        Metadata,
    },
    token::{transfer, Mint, Token, TokenAccount, Transfer},
};
use solana_program::{program::invoke_signed, rent::Rent, system_instruction::create_account};
use spl_token::error::TokenError;

// This is your program's public key and it will update
// automatically when you build the project.
declare_id!("8VN6kjfk3woA2PJeb2ucxNj46xTWFPN7n1M5pR8weyV3");

#[program]
mod hajime_ticket {
    use super::*;

    pub fn init_auth(ctx: Context<InitAuth>) -> Result<()> {
        msg!("init owner");

        let state = &mut ctx.accounts.owner_state;
        state.authority = ctx.accounts.authority.key();

        Ok(())
    }

    pub fn change_auth(ctx: Context<ChangeAuth>, new_auth: Pubkey) -> Result<()> {
        msg!("change owner");

        let state = &mut ctx.accounts.owner_state;
        state.authority = new_auth;

        Ok(())
    }

    pub fn init_nft(ctx: Context<InitNFT>, token_addr: Pubkey, token_price: u64) -> Result<()> {
        msg!("init transfer account");

        // make PDA as signer
        let (_, account_nonce) = Pubkey::find_program_address(
            &[NFT_ACCOUNT_PREFIX, &token_addr.to_bytes()],
            ctx.program_id,
        );
        let seeds = &[NFT_ACCOUNT_PREFIX, &token_addr.to_bytes(), &[account_nonce]];

        // create account
        let create_state_instruction = create_account(
            &ctx.accounts.authority.key(),
            &ctx.accounts.nft_account.key(),
            Rent::get()?.minimum_balance(0),
            0,
            &system_program::ID,
        );

        invoke_signed(
            &create_state_instruction,
            &[
                ctx.accounts.system_program.to_account_info().clone(),
                ctx.accounts.authority.to_account_info().clone(),
                ctx.accounts.nft_account.clone(),
            ],
            &[seeds],
        )?;

        msg!("init token state");

        let token_state = &mut ctx.accounts.token_state;
        token_state.token_addr = token_addr;
        token_state.price = token_price;
        token_state.next_edition = 1;

        Ok(())
    }

    fn set_price(ctx: Context<SetPrice>, _token_addr: Pubkey, new_price: u64) -> Result<()> {
        let token_state = &mut ctx.accounts.token_state;
        token_state.price = new_price;

        Ok(())
    }

    pub fn set_payment(ctx: Context<SetPayment>, token_addr: Pubkey) -> Result<()> {
        let (account, _) = Pubkey::find_program_address(
            &[NFT_ACCOUNT_PREFIX, &token_addr.to_bytes()],
            ctx.program_id,
        );

        let token_state = &mut ctx.accounts.token_state;
        let payment = &ctx.accounts.payment_token_account;

        if payment.owner != account {
            return Err(ProgramError::IllegalOwner.into());
        }

        msg!("set new payment");

        if !token_state.allow_tokens.contains(&payment.mint) {
            if token_state.allow_tokens.len() >= MAX_ALLOW_PAYMENTS {
                token_state.allow_tokens.remove(0);
            }

            token_state.allow_tokens.push(payment.mint.clone());
        }

        Ok(())
    }

    pub fn buy_nft(ctx: Context<BuyNFT>, token_addr: Pubkey) -> Result<()> {
        msg!("start buy");

        let token_state = &mut ctx.accounts.token_state;

        // make PDA as signer
        let (_, account_nonce) = Pubkey::find_program_address(
            &[NFT_ACCOUNT_PREFIX, &token_addr.to_bytes()],
            ctx.program_id,
        );
        let seeds = &[NFT_ACCOUNT_PREFIX, &token_addr.to_bytes(), &[account_nonce]];

        let destination = &ctx.accounts.payment_token_account;
        let source = &ctx.accounts.user_token_account;
        let token_program = &ctx.accounts.token_program;
        let authority = &ctx.accounts.user;

        if source.mint != destination.mint || !token_state.allow_tokens.contains(&source.mint) {
            return Err(ProgramError::InvalidArgument.into());
        }

        // Transfer tokens from taker to initializer
        let cpi_accounts = Transfer {
            from: source.to_account_info().clone(),
            to: destination.to_account_info().clone(),
            authority: authority.to_account_info().clone(),
        };
        let cpi_program = token_program.to_account_info();

        transfer(
            CpiContext::new_with_signer(cpi_program, cpi_accounts, &[seeds]),
            token_state.price,
        )?;

        msg!("print new edition");

        // get master edition
        let current_edition = token_state.next_edition - 1;
        let next_edition = current_edition
            .checked_add(1)
            .ok_or(ProgramError::Custom(TokenError::Overflow as u32))?;

        let edition_mint = ctx.accounts.edition_mint.to_account_info();
        let edition_token_account = ctx.accounts.edition_token.to_account_info();
        let master_token_account = ctx.accounts.nft_token_account.to_account_info();

        let mut builder = PrintV1CpiBuilder::new(&ctx.accounts.token_metadata_program);
        let builder = builder
            .edition(&ctx.accounts.edition)
            .edition_metadata(&ctx.accounts.edition_metadata)
            .master_edition(&ctx.accounts.master_edition)
            .edition_mint(&edition_mint, false)
            .edition_marker_pda(&ctx.accounts.edition_marker)
            .edition_mint_authority(&ctx.accounts.user)
            .payer(&ctx.accounts.user)
            .edition_token_account(&edition_token_account)
            .edition_token_account_owner(&ctx.accounts.user)
            .master_token_account_owner(&ctx.accounts.nft_account)
            .master_token_account(&master_token_account)
            .update_authority(&ctx.accounts.nft_account)
            .master_metadata(&ctx.accounts.master_edition_metadata)
            .edition_number(next_edition)
            .spl_token_program(&ctx.accounts.token_program)
            .spl_ata_program(&ctx.accounts.associated_token_program)
            .sysvar_instructions(&ctx.accounts.sysvar_instructions)
            .system_program(&ctx.accounts.system_program);

        builder.invoke_signed(&[seeds])?;

        token_state.next_edition += 1;

        Ok(())
    }

    pub fn claim_token(ctx: Context<ClaimToken>, token_addr: Pubkey, amount: u64) -> Result<()> {
        let mut claim = amount;
        let balance = ctx.accounts.payment_token_account.amount;
        if claim > balance {
            claim = balance;
        }

        msg!("prepare to claim {} tokens", claim);

        // make PDA as signer
        let (_, account_nonce) = Pubkey::find_program_address(
            &[NFT_ACCOUNT_PREFIX, &token_addr.to_bytes()],
            ctx.program_id,
        );
        let seeds = &[NFT_ACCOUNT_PREFIX, &token_addr.to_bytes(), &[account_nonce]];

        let destination = &ctx.accounts.user_token_account;
        let source = &ctx.accounts.payment_token_account;
        let token_program = &ctx.accounts.token_program;
        let authority = &ctx.accounts.nft_account;

        // Transfer tokens from taker to initializer
        let cpi_accounts = Transfer {
            from: source.to_account_info().clone(),
            to: destination.to_account_info().clone(),
            authority: authority.to_account_info().clone(),
        };
        let cpi_program = token_program.to_account_info();

        msg!("start transfer");

        transfer(
            CpiContext::new_with_signer(cpi_program, cpi_accounts, &[seeds]),
            claim,
        )?;

        Ok(())
    }
}

pub const NFT_ACCOUNT_PREFIX: &[u8] = b"hajime_bot_account";
pub const NFT_STATE_PREFIX: &[u8] = b"hajime_bot_state";

pub const MAX_ALLOW_PAYMENTS: usize = 5;

#[account]
#[derive(InitSpace)]
pub struct OwnerState {
    pub authority: Pubkey,
}

#[derive(Accounts)]
pub struct InitAuth<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(init, seeds = [b"owner"], bump, payer = authority, space = 8 + OwnerState::INIT_SPACE)]
    pub owner_state: Account<'info, OwnerState>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ChangeAuth<'info> {
    pub authority: Signer<'info>,
    #[account(mut, seeds = [b"owner"], bump, has_one = authority)]
    pub owner_state: Account<'info, OwnerState>,
}

#[account]
#[derive(InitSpace)]
pub struct TokenState {
    pub price: u64,
    pub next_edition: u64,
    pub token_addr: Pubkey,
    #[max_len(MAX_ALLOW_PAYMENTS)]
    pub allow_tokens: Vec<Pubkey>,
}

#[derive(Accounts)]
#[instruction(token_addr: Pubkey)]
pub struct InitNFT<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        mut,
        seeds = [b"owner"],
        bump,
        has_one = authority
    )]
    pub owner_state: Account<'info, OwnerState>,
    #[account(
        init,
        payer = authority,
        seeds = [NFT_STATE_PREFIX, &token_addr.key().as_ref()],
        bump,
        space = 8 + TokenState::INIT_SPACE
    )]
    pub token_state: Account<'info, TokenState>,
    /// CHECK: pass
    #[account(mut)]
    pub nft_account: AccountInfo<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(token_addr: Pubkey)]
pub struct SetPrice<'info> {
    pub authority: Signer<'info>,
    #[account(
        seeds = [b"owner"],
        bump,
        has_one = authority
    )]
    pub owner_state: Account<'info, OwnerState>,
    #[account(
        mut,
        seeds = [NFT_STATE_PREFIX, &token_addr.key().as_ref()],
        bump,
    )]
    pub token_state: Account<'info, TokenState>,
}

#[derive(Accounts)]
#[instruction(token_addr: Pubkey)]
pub struct SetPayment<'info> {
    pub authority: Signer<'info>,
    #[account(
        seeds = [b"owner"],
        bump,
        has_one = authority
    )]
    pub owner_state: Account<'info, OwnerState>,
    #[account(
        mut,
        seeds = [NFT_STATE_PREFIX, &token_addr.key().as_ref()],
        bump,
    )]
    pub token_state: Account<'info, TokenState>,
    pub payment_token_account: Account<'info, TokenAccount>,
}

#[derive(Accounts)]
#[instruction(token_addr: Pubkey)]
pub struct BuyNFT<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(
        mut,
        seeds = [NFT_STATE_PREFIX, &token_addr.key().as_ref()],
        bump
    )]
    pub token_state: Account<'info, TokenState>,
    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub payment_token_account: Account<'info, TokenAccount>,
    /// CHECK: pass
    pub nft_account: AccountInfo<'info>,
    pub nft_token_account: Account<'info, TokenAccount>,
    /// CHECK: pass
    #[account(mut)]
    pub master_edition: AccountInfo<'info>,
    /// CHECK: pass
    pub master_edition_metadata: UncheckedAccount<'info>,
    /// CHECK: pass
    #[account(mut)]
    pub edition_marker: AccountInfo<'info>,
    #[account(mut)]
    pub edition_mint: Account<'info, Mint>,
    /// CHECK: Address validated using constraint
    #[account(
        mut,
        address = MetadataAccount::find_pda(&edition_mint.key()).0
    )]
    pub edition_metadata: UncheckedAccount<'info>,
    /// CHECK: Address validated using constraint
    #[account(
        mut,
        address = MasterEdition::find_pda(&edition_mint.key()).0
    )]
    pub edition: UncheckedAccount<'info>,
    #[account(mut)]
    pub edition_token: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
    pub token_metadata_program: Program<'info, Metadata>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
    /// CHECK: pass
    pub sysvar_instructions: AccountInfo<'info>,
}

#[derive(Accounts)]
pub struct ClaimToken<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(
        seeds = [b"owner"],
        bump,
        has_one = authority
    )]
    pub owner_state: Account<'info, OwnerState>,
    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub payment_token_account: Account<'info, TokenAccount>,
    /// CHECK: pass
    pub nft_account: AccountInfo<'info>,
    pub token_program: Program<'info, Token>,
}