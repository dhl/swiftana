use mollusk_svm::Mollusk;
use solana_instruction::Instruction;
use solana_pubkey::Pubkey;
use solana_svm_log_collector::LogCollector;

#[test]
fn test_entrypoint_logs_hello_world() {
    let program_id = Pubkey::new_unique();
    let mut mollusk = Mollusk::new(&program_id, "./build/program");

    let logger = LogCollector::new_ref();
    mollusk.logger = Some(logger.clone());

    let instruction = Instruction {
        program_id,
        accounts: vec![],
        data: vec![],
    };

    let result = mollusk.process_instruction(&instruction, &[]);

    assert!(result.program_result.is_ok());

    let logs = logger.borrow();
    let messages = logs.get_recorded_content();

    let expected_message = "Hello world!";
    let has_hello_world = messages.iter().any(|log| log.contains(expected_message));

    assert!(has_hello_world, "Logs should contain '{expected_message}'");
}
