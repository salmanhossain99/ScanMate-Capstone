# 🔐 Environment Variables Setup Guide

This guide helps you securely store your Hugging Face token using environment variables instead of hardcoding it in your source code.

## 🚀 Quick Setup

### Step 1: Create .env File

1. **Navigate to your project directory**:
   ```bash
   cd flutter_doc_scanner-main/example/
   ```

2. **Create .env file** (copy from template):
   ```bash
   cp env_template.txt .env
   ```

3. **Edit .env file** with your actual token:
   ```bash
   # Open .env file in your editor
   nano .env  # or use your preferred editor
   ```

### Step 2: Configure Your Token

Replace the placeholder in `.env` file:

```env
# Hugging Face Configuration
HUGGING_FACE_TOKEN=your_actual_token_here

# AI Model Configuration
GEMMA_MODEL_URL=https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task
```

### Step 3: Verify Setup

1. **Run the app**:
   ```bash
   flutter run
   ```

2. **Check logs** - you should see:
   ```
   ✅ Environment variables loaded successfully
   🔑 Pre-filled token from environment
   ```

## 🛡️ Security Features

### Git Ignore Protection
- ✅ `.env` files are automatically ignored by Git
- ✅ Your tokens won't be committed to version control
- ✅ Safe to push to GitHub/GitLab

### Fallback System
- 🔄 If `.env` file is missing, app continues to work
- 🔄 Users can still manually enter tokens
- 🔄 Environment tokens are used automatically when available

## 🔧 Advanced Configuration

### Custom Model URL
You can specify a different model URL in your `.env` file:

```env
GEMMA_MODEL_URL=https://your-custom-model-url.com/model.task
```

### Multiple Environments
Create different `.env` files for different environments:

- `.env.development`
- `.env.production` 
- `.env.testing`

## 🐛 Troubleshooting

### Token Not Loading
1. **Check file location**: Ensure `.env` is in the `example/` directory
2. **Check file format**: No quotes around values, no spaces around `=`
3. **Check logs**: Look for "Environment variables loaded successfully"

### Git Still Detects Token
1. **Remove from staging**:
   ```bash
   git rm --cached .env
   git commit -m "Remove .env from tracking"
   ```

2. **Verify .gitignore**:
   ```bash
   echo ".env" >> .gitignore
   ```

### App Not Finding Environment
1. **Restart app completely**
2. **Clean build**:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

## 📁 File Structure

```
flutter_doc_scanner-main/
├── .gitignore                 # Contains .env ignore rules
├── env_template.txt          # Template for .env file
└── example/
    ├── .env                  # Your actual environment file (ignored by Git)
    ├── .gitignore           # Contains .env ignore rules
    ├── env_template.txt     # Template for .env file
    └── pubspec.yaml         # Contains flutter_dotenv dependency
```

## 🔑 Getting Hugging Face Token

### Option 1: Use Provided Token (Testing)
```
your_actual_token_here
```

### Option 2: Create Your Own Token
1. Go to [huggingface.co](https://huggingface.co)
2. Sign up for free account
3. Go to Settings → Access Tokens
4. Create new token with "Read" permissions
5. Copy token to your `.env` file

## ✅ Verification Checklist

- [ ] `.env` file created in `example/` directory
- [ ] Token added to `.env` file
- [ ] `.env` file is in `.gitignore`
- [ ] App runs without hardcoded tokens
- [ ] Environment variables load successfully
- [ ] Token auto-fills in AI setup screen
- [ ] Model downloads successfully

## 🎯 Benefits

✅ **Secure**: Tokens not in source code  
✅ **Flexible**: Easy to change tokens  
✅ **Git-Safe**: No accidental commits  
✅ **Team-Friendly**: Each developer uses own tokens  
✅ **CI/CD Ready**: Environment-based deployment  

Your app is now secure and ready for production deployment! 🚀
