use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount};
use wormhole_anchor_sdk::wormhole;

declare_id!("Capyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");

#[program]
pub mod capy_solana_token {
    use super::*;

    // Constants
    pub const INITIAL_SUPPLY: u64 = 1_000_000_000; // 1 billion tokens
    pub const LIQUIDITY_ALLOCATION: u64 = 400_000_000; // 40%
    pub const STAKING_ALLOCATION: u64 = 250_000_000; // 25%
    pub const DEVELOPMENT_ALLOCATION: u64 = 150_000_000; // 15%
    pub const MARKETING_ALLOCATION: u64 = 100_000_000; // 10%
    pub const TEAM_ALLOCATION: u64 = 100_000_000; // 10%

    // Vesting constants
    pub const TEAM_VESTING_DURATION: i64 = 63_072_000; // 2 years
    pub const TEAM_CLIFF_PERIOD: i64 = 31_536_000; // 1 year
    pub const DEVELOPMENT_VESTING_DURATION: i64 = 63_072_000; // 2 years
    pub const MARKETING_VESTING_PERIOD: i64 = 7_776_000; // 90 days

    // Transfer limits and tax
    pub const MAX_TRANSFER_AMOUNT: u64 = 1_000_000 * 1_000_000_000; // 1M tokens
    pub const TRANSFER_TAX_RATE: u64 = 2; // 2%

    #[state]
    pub struct CapySolanaToken {
        pub mint: Pubkey,
        pub authority: Pubkey,
        pub treasury_wallet: Pubkey,
        pub development_wallet: Pubkey,
        pub marketing_wallet: Pubkey,
        pub team_wallet: Pubkey,
        pub total_supply: u64,
        pub team_vesting_start: i64,
        pub development_vesting_start: i64,
        pub marketing_vesting_start: i64,
        pub paused: bool,
        pub wormhole_config: WormholeConfig,
    }

    #[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
    pub struct WormholeConfig {
        pub bridge: Pubkey,
        pub message_fee: u64,
        pub consistency_level: u8,
    }

    #[derive(AnchorSerialize, AnchorDeserialize, Clone)]
    pub struct StakeInfo {
        pub amount: u64,
        pub start_time: i64,
        pub last_claim_time: i64,
    }

    #[derive(AnchorSerialize, AnchorDeserialize, Clone)]
    pub struct VestingInfo {
        pub total_amount: u64,
        pub claimed_amount: u64,
        pub start_time: i64,
        pub duration: i64,
        pub cliff_period: Option<i64>,
    }

    #[account]
    pub struct UserStakeInfo {
        pub owner: Pubkey,
        pub stake_info: StakeInfo,
    }

    #[account]
    pub struct UserVestingInfo {
        pub owner: Pubkey,
        pub vesting_info: VestingInfo,
    }

    impl CapySolanaToken {
        pub fn initialize(
            ctx: Context<Initialize>,
            wormhole_config: WormholeConfig,
        ) -> Result<()> {
            let token = &mut ctx.accounts.token;
            token.authority = ctx.accounts.authority.key();
            token.mint = ctx.accounts.mint.key();
            token.treasury_wallet = ctx.accounts.treasury_wallet.key();
            token.development_wallet = ctx.accounts.development_wallet.key();
            token.marketing_wallet = ctx.accounts.marketing_wallet.key();
            token.team_wallet = ctx.accounts.team_wallet.key();
            token.total_supply = INITIAL_SUPPLY;
            token.team_vesting_start = Clock::get()?.unix_timestamp;
            token.development_vesting_start = Clock::get()?.unix_timestamp;
            token.marketing_vesting_start = Clock::get()?.unix_timestamp;
            token.wormhole_config = wormhole_config;
            token.paused = false;

            // Mint initial allocations
            token::mint_to(
                CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    token::MintTo {
                        mint: ctx.accounts.mint.to_account_info(),
                        to: ctx.accounts.treasury_wallet.to_account_info(),
                        authority: ctx.accounts.authority.to_account_info(),
                    },
                ),
                LIQUIDITY_ALLOCATION,
            )?;

            Ok(())
        }

        pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
            require!(amount >= 1000 * 1_000_000_000, StakeError::BelowMinimum); // 1000 tokens minimum
            
            let clock = Clock::get()?;
            let stake_info = StakeInfo {
                amount,
                start_time: clock.unix_timestamp,
                last_claim_time: clock.unix_timestamp,
            };

            let user_stake = &mut ctx.accounts.user_stake;
            user_stake.owner = ctx.accounts.owner.key();
            user_stake.stake_info = stake_info;

            token::transfer(
                CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    token::Transfer {
                        from: ctx.accounts.from.to_account_info(),
                        to: ctx.accounts.stake_vault.to_account_info(),
                        authority: ctx.accounts.owner.to_account_info(),
                    },
                ),
                amount,
            )?;

            Ok(())
        }

        pub fn unstake(ctx: Context<Unstake>) -> Result<()> {
            let user_stake = &ctx.accounts.user_stake;
            let amount = user_stake.stake_info.amount;

            // Claim rewards first
            Self::claim_rewards(ctx.accounts)?;

            token::transfer(
                CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    token::Transfer {
                        from: ctx.accounts.stake_vault.to_account_info(),
                        to: ctx.accounts.owner_token.to_account_info(),
                        authority: ctx.accounts.authority.to_account_info(),
                    },
                ),
                amount,
            )?;

            Ok(())
        }

        pub fn bridge_out(
            ctx: Context<BridgeOut>,
            amount: u64,
            recipient_chain: u16,
            recipient: [u8; 32],
        ) -> Result<()> {
            require!(!ctx.accounts.token.paused, TokenError::Paused);
            require!(amount > 0, TokenError::ZeroAmount);

            // Burn tokens
            token::burn(
                CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    token::Burn {
                        mint: ctx.accounts.mint.to_account_info(),
                        from: ctx.accounts.from.to_account_info(),
                        authority: ctx.accounts.owner.to_account_info(),
                    },
                ),
                amount,
            )?;

            // Post Wormhole message
            let message = BridgeMessage {
                amount,
                token_address: ctx.accounts.mint.key(),
                recipient_chain,
                recipient,
            };

            wormhole::post_message(
                CpiContext::new(
                    ctx.accounts.wormhole_program.to_account_info(),
                    wormhole::PostMessage {
                        config: ctx.accounts.config.to_account_info(),
                        message: ctx.accounts.message.to_account_info(),
                        emitter: ctx.accounts.emitter.to_account_info(),
                        sequence: ctx.accounts.sequence.to_account_info(),
                        payer: ctx.accounts.payer.to_account_info(),
                        fee_collector: ctx.accounts.fee_collector.to_account_info(),
                        clock: ctx.accounts.clock.to_account_info(),
                        rent: ctx.accounts.rent.to_account_info(),
                        system_program: ctx.accounts.system_program.to_account_info(),
                    },
                ),
                ctx.accounts.token.wormhole_config.consistency_level,
                message.try_to_vec()?,
                ctx.accounts.token.wormhole_config.message_fee,
            )?;

            Ok(())
        }

        pub fn bridge_in(
            ctx: Context<BridgeIn>,
            vaa: Vec<u8>,
        ) -> Result<()> {
            require!(!ctx.accounts.token.paused, TokenError::Paused);

            // Verify and parse VAA
            let parsed = wormhole::parse_vaa(&vaa)?;
            let message: BridgeMessage = BridgeMessage::try_from_slice(&parsed.payload)?;

            // Mint tokens to recipient
            token::mint_to(
                CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    token::MintTo {
                        mint: ctx.accounts.mint.to_account_info(),
                        to: ctx.accounts.recipient.to_account_info(),
                        authority: ctx.accounts.authority.to_account_info(),
                    },
                ),
                message.amount,
            )?;

            Ok(())
        }
    }
}

#[error_code]
pub enum TokenError {
    #[msg("Token transfer amount cannot be zero")]
    ZeroAmount,
    #[msg("Token transfers are paused")]
    Paused,
    #[msg("Transfer amount exceeds maximum")]
    ExceedsMaximum,
    #[msg("Insufficient balance")]
    InsufficientBalance,
}

#[error_code]
pub enum StakeError {
    #[msg("Stake amount below minimum")]
    BelowMinimum,
    #[msg("No rewards to claim")]
    NoRewards,
}

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct BridgeMessage {
    pub amount: u64,
    pub token_address: Pubkey,
    pub recipient_chain: u16,
    pub recipient: [u8; 32],
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = authority, mint::decimals = 9, mint::authority = authority)]
    pub mint: Account<'info, Mint>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub treasury_wallet: Account<'info, TokenAccount>,
    pub development_wallet: Account<'info, TokenAccount>,
    pub marketing_wallet: Account<'info, TokenAccount>,
    pub team_wallet: Account<'info, TokenAccount>,
    pub token: Account<'info, CapySolanaToken>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut)]
    pub owner: Signer<'info>,
    #[account(mut)]
    pub from: Account<'info, TokenAccount>,
    #[account(mut)]
    pub stake_vault: Account<'info, TokenAccount>,
    #[account(init, payer = owner)]
    pub user_stake: Account<'info, UserStakeInfo>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut)]
    pub owner: Signer<'info>,
    #[account(mut)]
    pub stake_vault: Account<'info, TokenAccount>,
    #[account(mut)]
    pub owner_token: Account<'info, TokenAccount>,
    #[account(mut)]
    pub authority: Signer<'info>,
    #[account(mut)]
    pub user_stake: Account<'info, UserStakeInfo>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct BridgeOut<'info> {
    #[account(mut)]
    pub owner: Signer<'info>,
    #[account(mut)]
    pub from: Account<'info, TokenAccount>,
    #[account(mut)]
    pub mint: Account<'info, Mint>,
    #[account(mut)]
    pub token: Account<'info, CapySolanaToken>,
    pub wormhole_program: Program<'info, wormhole::Wormhole>,
    pub config: Account<'info, wormhole::Config>,
    #[account(mut)]
    pub message: Account<'info, wormhole::Message>,
    pub emitter: Account<'info, wormhole::Emitter>,
    pub sequence: Account<'info, wormhole::Sequence>,
    pub payer: Account<'info, TokenAccount>,
    pub fee_collector: Account<'info, TokenAccount>,
    pub clock: Sysvar<'info, Clock>,
    pub rent: Sysvar<'info, Rent>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct BridgeIn<'info> {
    #[account(mut)]
    pub recipient: Account<'info, TokenAccount>,
    #[account(mut)]
    pub mint: Account<'info, Mint>,
    #[account(mut)]
    pub token: Account<'info, CapySolanaToken>,
    pub wormhole_program: Program<'info, wormhole::Wormhole>,
    pub authority: Signer<'info>,
    pub token_program: Program<'info, Token>,
}
