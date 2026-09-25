const webpack = require('webpack');
const path = require('path');
const ExtractTextPlugin = require('extract-text-webpack-plugin');

let mainStyle = new ExtractTextPlugin('main.bundle.css');
let cybStyle = new ExtractTextPlugin('cyb.bundle.css');
let angelicStyle = new ExtractTextPlugin('angelic.bundle.css');
let macosStyle = new ExtractTextPlugin('macos.bundle.css');
let bmStyle = new ExtractTextPlugin('bm.bundle.css');
let blameStyle = new ExtractTextPlugin('blame.bundle.css');

let config = {
  entry: {
    'main.bundle.css': './src/assets/stylesheets/main.css',
    'cyb.bundle.css': './src/assets/stylesheets/cyb.css',
    'angelic.bundle.css': './src/assets/stylesheets/angelic.css',
    'macos.bundle.css': './src/assets/stylesheets/macos.css',
    'bm.bundle.css': './src/assets/stylesheets/bm.css',
    'blame.bundle.css': './src/assets/stylesheets/blame.css',
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
      },      {
        test: /bm.css$/,
        exclude: /node_modules/,
        use: bmStyle.extract({
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
        test: /blame.css$/,
        exclude: /node_modules/,
        use: blameStyle.extract({
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
        // emitFile=false: the images already live in public/dist/images, the
        // very path this would write them to -- so every source image was
        // also webpack's output, read and written back over itself on each
        // build. With the watcher treating that write as a change, it looped,
        // and a second build running at the same moment read a 1.5 MB image
        // mid-write and saved it truncated at 512 KiB. Only the url()
        // rewriting is wanted; the files are served where they already are.
        use: [
          'file-loader?name=/images/[name].[ext]&emitFile=false'
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
    bmStyle,
    blameStyle,
  ],
  // For more info about webpack logs see: https://webpack.js.org/configuration/stats/
  stats: 'errors-only'
};

module.exports = config;
