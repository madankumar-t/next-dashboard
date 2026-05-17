const awsConfig = {
  region: process.env.REACT_APP_AWS_REGION || "us-east-2",
  cognito: {
    userPoolId: process.env.REACT_APP_USER_POOL_ID || "us-east-2_9YNsYJ5zG",
    userPoolClientId:
      process.env.REACT_APP_USER_POOL_CLIENT_ID ||
      "2qsoje021lqo2ptrgn8fut2d1p",
    domain:
      process.env.REACT_APP_COGNITO_DOMAIN ||
      "https://us-east-29ynsyj5zg.auth.us-east-2.amazoncognito.com",
    redirectSignIn:
      process.env.REACT_APP_REDIRECT_URI ||
      "https://d3v9zvdkoc9r6x.cloudfront.net/auth/callback",
    redirectSignOut:
      process.env.REACT_APP_SIGNOUT_URI ||
      "https://d3v9zvdkoc9r6x.cloudfront.net/",
    responseType: "code",
  },
  dynamodb: {
    tableData:
      process.env.REACT_APP_DYNAMODB_TABLE_DATA ||
      "inventory-dashboard-dev-inventory-data",
    tableMetadata:
      process.env.REACT_APP_DYNAMODB_TABLE_METADATA ||
      "inventory-dashboard-dev-inventory-metadata",
  },
  lambda: {
    inventory:
      process.env.REACT_APP_LAMBDA_INVENTORY ||
      "inventory-dashboard-dev-inventory",
    refresh:
      process.env.REACT_APP_LAMBDA_REFRESH || "inventory-dashboard-dev-refresh",
  },
};

export default awsConfig;
