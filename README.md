
# FiniteMonkey

<p align="center">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue.svg">
  <img src="https://img.shields.io/badge/version-1.0-green.svg">
  <img src="https://img.shields.io/badge/bounties-$60,000+-yellow.svg">
  <img src="https://img.shields.io/github/forks/BradMoonUESTC/finite-monkey-engine?style=flat-square">
  <img src="https://img.shields.io/github/stars/BradMoonUESTC/finite-monkey-engine?style=flat-square">
</p>

FiniteMonkey is an advanced vulnerability mining engine powered purely by GPT, requiring no prior knowledge base or fine-tuning. Its effectiveness significantly surpasses most current related research approaches.

## 🌟 Core Philosophy

- **Task-driven, not question-driven**
- **Prompt-driven, not code-driven** 
- **Focus on prompt design, not model design**
- **Leveraging "deception" and hallucination as key mechanics**

## 🏆 Results

As of May 2024, this tool has helped identify vulnerabilities worth over $60,000 in bounties.

<img width="1258" alt="Bounty Results" src="https://github.com/BradMoonUESTC/trickPrompt-engine/assets/63706549/b3812927-2aa9-47bf-a848-753c2fe05d98">

## 🚀 Recent Updates

**2024.11.19**: Version 1.0 released - Demonstrating feasibility of LLM-based auditing and productization

**Earlier Updates:**
- 2024.08.02: Project renamed to finite-monkey-engine
- 2024.08.01: Added support for func, tact
- 2024.07.23: Added support for cairo, move
- 2024.07.01: Updated license
- 2024.06.01: Added Python language support
- 2024.05.18: Improved false positive reduction (~20%)
- 2024.05.16: Added cross-contract vulnerability confirmation
- 2024.04.29: Added basic Rust language support

## 📋 Prerequisites

- PostgreSQL database
- OpenAI API access
- Python environment

## 🛠️ Setup & Configuration

1. Place project under `src/dataset/agent-v1-c4`

2. Configure project in `datasets.json`:
```json
{
    "StEverVault2": {
        "path": "StEverVault",
        "files": [],
        "functions": []
    }
}
```

3. Create database using `src/db.sql`

4. Configure `.env`:
```env
# Database Connection
DATABASE_URL=postgresql://user:password@localhost:5432/dbname

# API Settings
OPENAI_API_BASE="api.example.com"
OPENAI_API_KEY=sk-your-api-key-here

# Model Settings
VUL_MODEL_ID=gpt-4-turbo
CLAUDE_MODEL=claude-3-5-sonnet-20240620

# Azure Configuration
AZURE_API_KEY="your-azure-api-key"
AZURE_API_BASE="https://your-resource.openai.azure.com/"
AZURE_API_VERSION="2024-02-15-preview"
AZURE_DEPLOYMENT_NAME="your-deployment"

# API Choice
AZURE_OR_OPENAI="OPENAI"  # Options: OPENAI, AZURE, CLAUDE

# Scan Parameters
BUSINESS_FLOW_COUNT=4
SWITCH_FUNCTION_CODE=False
SWITCH_BUSINESS_CODE=True

# Scan Focus Configuration
# SCAN_FOCUS=[
#     "Contract1",
#     "Contract2",
#     "Contract3"
# ]
```
## 🌈 Supported Languages

- Solidity (.sol)
- Rust (.rs)
- Python (.py)
- Move (.move)
- Cairo (.cairo)
- Tact (.tact)
- Func (.fc)
- Java (.java)
- Fake Solidity (.fr) - For scanning Solidity pseudocode


## 📊 Scanning Results Guide

1. Scans can be resumed if interrupted due to network/API issues by rerunning main.py with same project_id
2. Strongly recommend using GPT-4-turbo - GPT-3.5 and GPT-4.0 have inferior reasoning capabilities
3. Results are marked with detailed annotations and Chinese explanations:
   - Prioritize entries with `"result":"yes"` in result column
   - Filter for `"dont need In-project other contract"` in category column
   - Check business_flow_code column for specific code
   - Reference name column for code locations

## 🎯 Important Notes

- Best suited for logic vulnerability mining in real projects
- Not recommended for academic vulnerability testing
- GPT-4-turbo recommended for optimal results
- Average scan time: 2-3 hours for medium projects
- Cost estimate: $20-30 for medium projects with 10 iterations
- Current false positive rate: 30-65% depending on project size

## 🔍 Technical Notes

1. GPT-4 provides better results, GPT-3 not thoroughly tested
2. The tricky prompt theory can be adapted for any language with minor modifications
3. ANTLR AST parsing support recommended for better code slicing results
4. Currently supports Solidity with plans for expansion

## 🗺️ Roadmap

1. Code structure optimization
2. Additional language support
3. Documentation and code analysis
4. Command line interface implementation

## 🛡️ Scanning Characteristics

- Excellent at code comprehension and logic vulnerability detection
- Less effective for control flow vulnerability detection
- Designed for real-world projects rather than academic test cases

## 💡 Implementation Tips

- Each scan preserves progress automatically
- GPT-4-turbo provides optimal performance compared to other models
- Medium projects with 10 iterations take approximately 2.5 hours
- Results include detailed categorization and Chinese explanations

## 📝 License

GNU General Public License v3.0 (GPL-3.0)

## 🤝 Contributing

Contributions welcome! Please feel free to submit pull requests.

---

*Note: The name is inspired by [Large Language Monkeys paper](https://arxiv.org/abs/2407.21787v1)*
