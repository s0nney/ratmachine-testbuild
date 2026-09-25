const webpack = require('webpack');
const path = require('path');
const ExtractTextPlugin = require('extract-text-webpack-plugin');

let mainStyle = new ExtractTextPlugin('main.bundle.css');
let cybStyle = new ExtractTextPlugin('cyb.bundle.css');
let angelicStyle = new ExtractTextPlugin('angelic.bundle.css');
let macosStyle = new ExtractTextPlugin('macos.bundle.css');

let config = {
  entry: {
    'main.bundle.css': './src/assets/stylesheets/main.css',
    'cyb.bundle.css': './src/assets/stylesheets/cyb.css',
    'angelic.bundle.css': './src/assets/stylesheets/angelic.css',
    'macos.bundle.css': './src/assets/stylesheets/macos.css',
  },
  output: {
    filename: '[name]',
    path: path.resolve(__dirname, '../../public/dist'),
    publicPath: '/dist'
  },
  resolve: {
    alias: {
      amber: path.resolve(__dirname, '../../lib/amber/assets/js/amber.js')
    }
  },
  module: {
    rules: [
      {
        test: /main.css$/,
        exclude: /node_modules/,
        use: mainStyle.extract({
          fallback: 'style-loader',
          use: {
            loader: 'css-loader',
            options: {
              minimize: true
            }
          }
        })
      },
      {
        test: /cyb.css$/,
        exclude: /node_modules/,
        use: cybStyle.extract({
          fallback: 'style-loader',
          use: {
            loader: 'css-loader',
            options: {
              minimize: true
            }
          }
        })
      },
      {
        test: /angelic.css$/,
        exclude: /node_modules/,
        use: angelicStyle.extract({
          fallback: 'style-loader',
          use: {
            loader: 'css-loader',
            options: {
              minimize: true
            }
          }
        })
      },      {
        test: /macos.css$/,
        exclude: /node_modules/,
        use: macosStyle.extract({
          fallback: 'style-loader',
          use: {
            loader: 'css-loader',
            options: {
              minimize: true
            }
          }
        })
      },
      {
        test: /\.(png|svg|jpg|apng|gif)$/,
        exclude: /node_modules/,
        use: [
          'file-loader?name=/images/[name].[ext]'
        ]
      },
      {
        test: /\.(woff|woff2|eot|ttf|otf)$/,
        exclude: /node_modules/,
        use: [
          'file-loader?name=/[name].[ext]'
        ]
      },
      {
        test: /\.js?$/,
        exclude: /node_modules/,
        loader: 'babel-loader',
        query: {
          presets: ['env']
        }
      }
    ]
  },
  plugins: [
    mainStyle,
    cybStyle,
    angelicStyle,
    macosStyle,
  ],
  // For more info about webpack logs see: https://webpack.js.org/configuration/stats/
  stats: 'errors-only'
};

module.exports = config;
