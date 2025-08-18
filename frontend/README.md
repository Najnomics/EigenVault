# EigenVault Frontend

A modern, responsive frontend for the EigenVault privacy-preserving trading infrastructure built with React, Vite, and Tailwind CSS.

## 🚀 Features

- **Order Submission**: Submit large orders for private matching through the vault
- **Vault Monitoring**: Real-time status monitoring of vault operations
- **Operator Management**: View and monitor AVS operator performance
- **Responsive Design**: Mobile-first design that works on all devices
- **Modern UI**: Beautiful, intuitive interface with smooth animations

## 🛠️ Tech Stack

- **React 18** - Modern React with hooks and functional components
- **Vite** - Fast build tool and development server
- **Tailwind CSS** - Utility-first CSS framework
- **Ethers.js** - Ethereum library for blockchain interactions
- **React Router** - Client-side routing
- **Radix UI** - Accessible UI components

## 📋 Prerequisites

- Node.js 18+ 
- Yarn or npm
- Modern web browser

## 🚀 Getting Started

### 1. Install Dependencies

```bash
cd frontend
yarn install
# or
npm install
```

### 2. Environment Configuration

Create a `.env` file in the frontend directory:

```env
# Ethereum RPC URLs
VITE_ETHEREUM_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR_API_KEY
VITE_POLYGON_RPC_URL=https://polygon-rpc.com

# Contract Addresses (update with deployed addresses)
VITE_EIGENVAULT_HOOK_ADDRESS=0x...
VITE_ORDER_VAULT_ADDRESS=0x...
VITE_SERVICE_MANAGER_ADDRESS=0x...

# Network Configuration
VITE_CHAIN_ID=1
VITE_NETWORK_NAME=mainnet
```

### 3. Start Development Server

```bash
yarn dev
# or
npm run dev
```

The frontend will be available at `http://localhost:3000`

### 4. Build for Production

```bash
yarn build
# or
npm run build
```

### 5. Preview Production Build

```bash
yarn preview
# or
npm run preview
```

## 🏗️ Project Structure

```
frontend/
├── public/                 # Static assets
├── src/
│   ├── components/         # React components
│   │   ├── OrderForm.jsx   # Order submission form
│   │   ├── VaultStatus.jsx # Vault monitoring dashboard
│   │   ├── OperatorList.jsx # AVS operator management
│   │   └── *.css          # Component-specific styles
│   ├── hooks/              # Custom React hooks
│   ├── lib/                # Utility libraries
│   ├── App.jsx             # Main application component
│   ├── main.jsx            # Application entry point
│   ├── App.css             # Main application styles
│   └── index.css           # Global styles and Tailwind
├── index.html              # HTML template
├── vite.config.js          # Vite configuration
├── tailwind.config.js      # Tailwind CSS configuration
├── postcss.config.js       # PostCSS configuration
└── package.json            # Dependencies and scripts
```

## 🎨 Component Overview

### OrderForm
- **Purpose**: Submit large orders to the EigenVault system
- **Features**: 
  - Pool selection
  - Order type (buy/sell)
  - Amount and price inputs
  - Commitment generation
  - Order encryption
  - Form validation

### VaultStatus
- **Purpose**: Monitor vault operations and order status
- **Features**:
  - Real-time statistics
  - Recent activity feed
  - Vault health indicators
  - Order tracking

### OperatorList
- **Purpose**: Monitor AVS operator performance
- **Features**:
  - Operator statistics
  - Performance metrics
  - Network information
  - Stake monitoring

## 🔧 Configuration

### Vite Configuration
The `vite.config.js` file includes:
- React plugin for JSX support
- Path aliases for clean imports
- Development server configuration
- Build optimization settings

### Tailwind Configuration
The `tailwind.config.js` file includes:
- Custom color palette
- Responsive breakpoints
- Component variants
- Animation utilities

## 📱 Responsive Design

The frontend is built with a mobile-first approach:
- **Mobile**: Single-column layout with stacked components
- **Tablet**: Two-column grid for medium screens
- **Desktop**: Full three-column layout with sidebars

## 🧪 Testing

```bash
# Run tests
yarn test

# Run tests in watch mode
yarn test:watch

# Run tests with coverage
yarn test:coverage
```

## 🚀 Deployment

### Vercel
```bash
# Install Vercel CLI
npm i -g vercel

# Deploy
vercel
```

### Netlify
```bash
# Build the project
yarn build

# Deploy the dist folder to Netlify
```

### Traditional Hosting
```bash
# Build the project
yarn build

# Upload the dist folder to your web server
```

## 🔒 Security Considerations

- **Environment Variables**: Never commit `.env` files to version control
- **API Keys**: Use environment variables for sensitive configuration
- **HTTPS**: Always use HTTPS in production
- **Input Validation**: All user inputs are validated on both client and server

## 🐛 Troubleshooting

### Common Issues

1. **Port 3000 already in use**
   ```bash
   # Kill the process using port 3000
   lsof -ti:3000 | xargs kill -9
   ```

2. **Dependencies not installing**
   ```bash
   # Clear cache and reinstall
   rm -rf node_modules yarn.lock
   yarn install
   ```

3. **Build errors**
   ```bash
   # Check for TypeScript errors
   yarn type-check
   
   # Lint the code
   yarn lint
   ```

### Development Tips

- Use the browser's developer tools to debug React components
- Check the console for any JavaScript errors
- Use React DevTools extension for component inspection
- Monitor network requests in the Network tab

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

## 🆘 Support

For support and questions:
- Create an issue in the repository
- Check the documentation
- Join the community Discord

---

**Built with ❤️ for the EigenVault project**
